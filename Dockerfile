# Builds the hologram-generic-ai-agent-vs chatbot from the upstream source.
# Your customizations live in agent-packs/ and docs/ — mounted as volumes at runtime.

# Stage 1: clone & build upstream source
FROM node:23-alpine AS builder
RUN apk add --no-cache git
WORKDIR /upstream
RUN git clone --depth 1 --branch v1.9.0 https://github.com/2060-io/hologram-generic-ai-agent-vs.git .

# No CoreModule patch needed — AppModule handles StatProducerService via
# EventsModule.register({ modules: { stats: true } }) when VS_AGENT_STATS_ENABLED=true

# Patch: make RAG embeddings provider-aware (Ollama or OpenAI based on LLM_PROVIDER)
RUN apk add --no-cache python3 && python3 - <<'EOF'
path = 'src/rag/langchain-rag.service.ts'
src = open(path).read()

# 1. Add OllamaEmbeddings import alongside the existing OpenAI import
src = src.replace(
    "import { OpenAIEmbeddings, OpenAI } from '@langchain/openai'",
    "import { OpenAIEmbeddings, OpenAI } from '@langchain/openai'\nimport { OllamaEmbeddings } from '@langchain/ollama'"
)

# 2. Change the embeddings variable type to accept both providers
src = src.replace(
    "    let embeddings: OpenAIEmbeddings",
    "    let embeddings: OpenAIEmbeddings | OllamaEmbeddings"
)

# 3. Replace the hardcoded OpenAI embeddings init with a provider-conditional block
old_block = """    try {
      embeddings = new OpenAIEmbeddings({ openAIApiKey: openaiApiKey! })
      this.logger.debug('OpenAI embeddings initialized successfully.')
    } catch (error) {
      this.logger.error(`Failed to initialize OpenAI embeddings: ${error.message}`)
      return
    }"""

new_block = """    const llmProvider = process.env.LLM_PROVIDER || 'openai'
    try {
      if (llmProvider === 'ollama') {
        const ollamaBaseUrl = process.env.OLLAMA_ENDPOINT || 'http://localhost:11434'
        const ollamaEmbeddingModel = process.env.OLLAMA_EMBEDDING_MODEL || 'nomic-embed-text'
        embeddings = new OllamaEmbeddings({ model: ollamaEmbeddingModel, baseUrl: ollamaBaseUrl })
        this.logger.debug(`Ollama embeddings initialized (model=${ollamaEmbeddingModel}, url=${ollamaBaseUrl}).`)
      } else {
        embeddings = new OpenAIEmbeddings({ openAIApiKey: openaiApiKey! })
        this.logger.debug('OpenAI embeddings initialized successfully.')
      }
    } catch (error) {
      this.logger.error(`Failed to initialize embeddings: ${error.message}`)
      return
    }"""

src = src.replace(old_block, new_block)

# 4. Update private method signatures to accept both embedding types
src = src.replace(
    "private async initPinecone(embeddings: OpenAIEmbeddings)",
    "private async initPinecone(embeddings: OpenAIEmbeddings | OllamaEmbeddings)"
)
src = src.replace(
    "private async initRedis(embeddings: OpenAIEmbeddings)",
    "private async initRedis(embeddings: OpenAIEmbeddings | OllamaEmbeddings)"
)

open(path, 'w').write(src)
print('RAG embedding patch applied successfully')
EOF

# Patch: add anthropicModel to app config (upstream omits it, defaulting to 'claude-3')
RUN python3 - <<'EOF'
path = 'src/config/app.config.ts'
src = open(path).read()
src = src.replace(
    "anthropicApiKey: process.env.ANTHROPIC_API_KEY || '',",
    "anthropicApiKey: process.env.ANTHROPIC_API_KEY || '',\n    anthropicModel: pickString('ANTHROPIC_MODEL', agentPack?.llm?.model, 'claude-haiku-4-5-20251001'),"
)
open(path, 'w').write(src)
print('Anthropic model patch applied successfully')
EOF

# Patch: extract text from Claude content-block arrays (Claude 4.x returns [{type,text}] not strings)
RUN python3 - <<'EOF'
import re

# ── 1. llm.service.ts — return plain text instead of JSON.stringify(array) ──
path = 'src/llm/llm.service.ts'
src = open(path).read()
old = "this.logger.warn('Agent executor returned a non-string result. Returning JSON stringified result.')\n        return this.sanitizeResponse(JSON.stringify(output))"
new = """if (Array.isArray(output)) {
          const text = output
            .filter((b: any) => b.type === 'text' && typeof b.text === 'string')
            .map((b: any) => b.text)
            .join('\\n')
          if (text) {
            this.logger.log('Agent executor returned content-block array. Extracted text.')
            return this.sanitizeResponse(text)
          }
        }
        this.logger.warn('Agent executor returned a non-string result. Returning JSON stringified result.')
        return this.sanitizeResponse(JSON.stringify(output))"""
if old in src:
    src = src.replace(old, new)
    open(path, 'w').write(src)
    print('llm.service.ts patch applied')
else:
    print('WARNING: llm.service.ts patch target not found — skipping')

# ── 2. langchain-session-memory.ts — save plain text, not raw content blocks ──
path = 'src/memory/langchain-session-memory.ts'
src = open(path).read()
old = "const aiOutput = (output.output ?? output.response ?? '') as string"
new = """const rawAiOutput = output.output ?? output.response ?? ''
    const aiOutput: string = Array.isArray(rawAiOutput)
      ? rawAiOutput.filter((b: any) => b.type === 'text' && typeof b.text === 'string').map((b: any) => b.text).join('\\n')
      : String(rawAiOutput)"""
if old in src:
    src = src.replace(old, new)
    open(path, 'w').write(src)
    print('langchain-session-memory.ts patch applied')
else:
    print('WARNING: langchain-session-memory.ts patch target not found — skipping')
EOF

# Patch: wire RAG context into chatbot (upstream passes '' as context; fix to pre-fill from docs)
RUN python3 - <<'EOF'

# ── 1. chatbot.module.ts — import RagModule so RagService is injectable ──
path = 'src/chatbot/chatbot.module.ts'
src = open(path).read()
if 'RagModule' not in src:
    src = src.replace(
        "import { LlmModule } from 'src/llm/llm.module'",
        "import { LlmModule } from 'src/llm/llm.module'\nimport { RagModule } from 'src/rag/rag.module'"
    )
    src = src.replace(
        "imports: [LlmModule]",
        "imports: [LlmModule, RagModule]"
    )
    open(path, 'w').write(src)
    print('chatbot.module.ts patched')
else:
    print('chatbot.module.ts already has RagModule')

# ── 2. chatbot.service.ts — inject RagService and pre-fill context ──
path = 'src/chatbot/chatbot.service.ts'
src = open(path).read()
if 'ragService' not in src:
    src = src.replace(
        "import { LlmService } from '../llm/llm.service'",
        "import { LlmService } from '../llm/llm.service'\nimport { RagService } from '../rag/rag.service'"
    )
    src = src.replace(
        "constructor(private readonly llmService: LlmService) {}",
        "constructor(private readonly llmService: LlmService, private readonly ragService: RagService) {}"
    )
    src = src.replace(
        "const prompt = template('', userInput, userName)",
        "const contextChunks = await this.ragService.retrieveContext(userInput)\n    const context = contextChunks.join('\\n---\\n')\n    const prompt = template(context, userInput, userName)"
    )
    open(path, 'w').write(src)
    print('chatbot.service.ts patched')
else:
    print('chatbot.service.ts already patched')

# ── 3. vector-store.service.ts — keyword search for non-OpenAI providers ──
path = 'src/rag/vector-store.service.ts'
src = open(path).read()
old = "  async retrieveContext(query: string): Promise<string[]> {"
new = """  private keywordSearch(query: string, topK = 3): string[] {
    const words = query.toLowerCase().split(/\\s+/).filter(w => w.length > 2)
    if (!words.length) return []
    const scored = this.docs.map(doc => ({
      text: doc.text,
      score: words.filter(w => doc.text.toLowerCase().includes(w)).length,
    }))
    return scored
      .sort((a, b) => b.score - a.score)
      .slice(0, topK)
      .filter(r => r.score > 0)
      .map(r => r.text)
  }

  async retrieveContext(query: string): Promise<string[]> {"""
if old in src and 'keywordSearch' not in src:
    src = src.replace(old, new)
    src = src.replace(
        "    const results = await this.query(query, 3)",
        "    if (this.llmProvider !== 'openai') return this.keywordSearch(query)\n    const results = await this.query(query, 3)"
    )
    open(path, 'w').write(src)
    print('vector-store.service.ts patched with keyword search')
else:
    print('vector-store.service.ts already patched or pattern not found')
EOF

RUN npm install -g pnpm && pnpm install --frozen-lockfile && pnpm run build

# Stage 2: lean runtime image
FROM node:23-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder /upstream/dist ./dist
COPY --from=builder /upstream/node_modules ./node_modules
COPY --from=builder /upstream/package.json ./

EXPOSE 3000
CMD ["node", "dist/main.js"]
