<script setup>
// admin 卡面生成工作台(#/admin/cards):
// OpenAI key 只存瀏覽器 localStorage,隨請求傳後端代理呼叫,後端不落地。
// 權限由後端 AdminAuth 把關(Bearer = ADMIN_TOKEN 或 admin Discord token)。
import { computed, onMounted, onUnmounted, ref } from 'vue'
import { useSettingsStore } from '../stores/settings'

const OPENAI_KEY = 'gm_openai_key'

const settings = useSettingsStore()

const apiKey = ref(localStorage.getItem(OPENAI_KEY) || '')
const model = ref('gpt-image-2')
const size = ref('1024x1536')
const n = ref(1)
const prompt = ref('')

const generating = ref(false)
const forbidden = ref(false)
const lastError = ref('')
/** @type {import('vue').Ref<object[]>} */
const history = ref([])

/** 與 UserSocket 同邏輯:Discord token 優先,否則訪客 token(= ADMIN_TOKEN 場合) */
const authToken = computed(() => settings.discordToken || settings.token)

function saveKey() {
  localStorage.setItem(OPENAI_KEY, apiKey.value)
}

async function api(path, options = {}) {
  const resp = await fetch(`/api/admin/card-art${path}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${authToken.value}`,
      ...options.headers,
    },
  })
  if (resp.status === 403) {
    forbidden.value = true
    throw new Error('需要 admin 權限')
  }
  return resp
}

async function loadHistory() {
  try {
    const resp = await api('/history')
    history.value = await resp.json()
  } catch {
    /* forbidden 已標記 */
  }
}

async function generate() {
  if (generating.value || !prompt.value.trim()) return
  lastError.value = ''
  generating.value = true
  try {
    const resp = await api('/generate', {
      method: 'POST',
      body: JSON.stringify({
        api_key: apiKey.value,
        prompt: prompt.value,
        model: model.value,
        size: size.value,
        n: n.value,
      }),
    })
    const record = await resp.json()
    if (record.error && !record.id) {
      lastError.value = record.error
    } else {
      history.value = [record, ...history.value]
      if (record.error_msg) lastError.value = record.error_msg
    }
  } catch (error) {
    lastError.value = String(error)
  } finally {
    generating.value = false
  }
}

// —— batch 輪詢:pending 紀錄由前端帶 key 定期查核(後端不留 key) ——

const checking = ref(false)
const hasPending = computed(() => history.value.some((h) => h.status === 'pending'))

async function checkBatches() {
  if (checking.value || !apiKey.value || !hasPending.value) return
  checking.value = true
  try {
    const resp = await api('/check', {
      method: 'POST',
      body: JSON.stringify({ api_key: apiKey.value }),
    })
    const body = await resp.json()
    if (body.history) history.value = body.history
  } catch {
    /* 下輪再試 */
  } finally {
    checking.value = false
  }
}

/** @type {ReturnType<typeof setInterval> | null} */
let pollTimer = null
onMounted(() => {
  pollTimer = setInterval(checkBatches, 30_000)
})
onUnmounted(() => {
  if (pollTimer) clearInterval(pollTimer)
})

const STATUS_META = {
  pending: { icon: '⏳', label: '處理中' },
  completed: { icon: '✓', label: '完成' },
  failed: { icon: '✗', label: '失敗' },
}

/** @param {string} iso */
function fmtTime(iso) {
  return iso ? iso.replace('T', ' ').slice(5, 19) : ''
}

/** @param {number | null} ms */
function fmtDuration(ms) {
  if (ms == null) return '—'
  return ms >= 1000 ? `${(ms / 1000).toFixed(1)}s` : `${ms}ms`
}

onMounted(loadHistory)
</script>

<template>
  <div class="admin-cards">
    <header class="ac-head">
      <h1>卡面生成工作台 <span class="ac-sub">admin</span></h1>
      <router-link class="btn ghost" to="/gallery">圖鑑</router-link>
    </header>

    <div v-if="forbidden" class="ac-forbidden">
      需要 admin 權限——請用 admin Discord 帳號登入,或將 localStorage 的
      <code>gm_token</code> 設為 ADMIN_TOKEN 後重整。
    </div>

    <template v-else>
      <section class="ac-form">
        <label class="ac-field ac-wide">
          <span>OpenAI API key(只存在此瀏覽器)</span>
          <input v-model="apiKey" type="password" placeholder="sk-..." @change="saveKey" />
        </label>
        <div class="ac-row">
          <label class="ac-field">
            <span>model</span>
            <select v-model="model">
              <option value="gpt-image-2">gpt-image-2</option>
              <option value="gpt-image-1">gpt-image-1</option>
            </select>
          </label>
          <label class="ac-field">
            <span>size</span>
            <select v-model="size">
              <option value="1024x1536">1024×1536 直向</option>
              <option value="1024x1024">1024×1024</option>
              <option value="1536x1024">1536×1024 橫向</option>
              <option value="auto">auto</option>
            </select>
          </label>
          <label class="ac-field">
            <span>張數(1–8)</span>
            <input v-model.number="n" type="number" min="1" max="8" />
          </label>
        </div>
        <label class="ac-field ac-wide">
          <span>prompt</span>
          <textarea v-model="prompt" rows="5" placeholder="ligne claire comic illustration, ..."></textarea>
        </label>
        <button class="btn primary" :disabled="generating || !apiKey || !prompt.trim()" @click="generate">
          {{ generating ? '建立 batch 中…' : '⚡ 送出 batch(半價,結果稍後回)' }}
        </button>
        <p v-if="lastError" class="ac-error">{{ lastError }}</p>
      </section>

      <section>
        <h2 class="ac-h2">
          生成紀錄
          <button
            v-if="hasPending"
            class="btn ghost ac-check"
            :disabled="checking || !apiKey"
            @click="checkBatches"
          >
            {{ checking ? '查核中…' : '🔄 立即查核 batch' }}
          </button>
          <span v-if="hasPending" class="ac-poll-hint">每 30 秒自動查核</span>
        </h2>
        <div class="ac-table-wrap">
          <table class="ac-table">
            <thead>
              <tr>
                <th>時間</th>
                <th>狀態</th>
                <th>model</th>
                <th>size</th>
                <th>圖</th>
                <th>tokens</th>
                <th>耗時</th>
                <th>prompt</th>
                <th>錯誤</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="h in history" :key="h.id">
                <td class="ac-nowrap">{{ fmtTime(h.inserted_at) }}</td>
                <td class="ac-nowrap" :class="`ac-st-${h.status}`">
                  {{ STATUS_META[h.status]?.icon }} {{ STATUS_META[h.status]?.label || h.status }}
                </td>
                <td>{{ h.model }}</td>
                <td>{{ h.size || 'auto' }}</td>
                <td class="ac-thumbs">
                  <a v-for="url in h.urls" :key="url" :href="url" target="_blank" rel="noreferrer">
                    <img :src="url" alt="" loading="lazy" />
                  </a>
                  <span v-if="!h.urls?.length">—</span>
                </td>
                <td>{{ h.tokens ?? '—' }}</td>
                <td>{{ fmtDuration(h.duration_ms) }}</td>
                <td class="ac-prompt" :title="h.prompt">{{ h.prompt }}</td>
                <td class="ac-error-cell" :title="h.error_msg || ''">{{ h.error_msg || '' }}</td>
              </tr>
              <tr v-if="!history.length">
                <td colspan="9" class="ac-empty">還沒有紀錄</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>
  </div>
</template>

<style scoped>
.admin-cards {
  width: 100%;
  max-width: 1100px;
  margin: 0 auto;
  padding: 16px;
}

.ac-head {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  margin-bottom: 14px;
}

.ac-head h1 {
  font-size: 1.2rem;
  color: var(--text-bright);
}

.ac-sub {
  font-size: 0.75rem;
  color: var(--red, #f87171);
  margin-left: 8px;
  text-transform: uppercase;
}

.ac-forbidden {
  border: 1px solid var(--red, #f87171);
  border-radius: 8px;
  padding: 14px;
  color: var(--text);
}

.ac-form {
  display: flex;
  flex-direction: column;
  gap: 10px;
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 14px;
  background: var(--bg-raised);
  margin-bottom: 20px;
}

.ac-row {
  display: flex;
  gap: 10px;
  flex-wrap: wrap;
}

.ac-field {
  display: flex;
  flex-direction: column;
  gap: 4px;
  font-size: 0.75rem;
  color: var(--text-dim);
}

.ac-field input,
.ac-field select,
.ac-field textarea {
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 6px;
  color: var(--text);
  padding: 6px 8px;
  font: inherit;
}

.ac-wide {
  width: 100%;
}

.ac-error {
  color: var(--red, #f87171);
  font-size: 0.8rem;
  white-space: pre-wrap;
}

.ac-h2 {
  font-size: 0.95rem;
  color: var(--text-bright);
  margin-bottom: 8px;
}

.ac-table-wrap {
  overflow-x: auto;
}

.ac-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 0.75rem;
}

.ac-table th,
.ac-table td {
  border-bottom: 1px solid var(--border);
  padding: 6px 8px;
  text-align: left;
  vertical-align: top;
  color: var(--text);
}

.ac-table th {
  color: var(--text-dim);
  font-weight: 600;
}

.ac-nowrap {
  white-space: nowrap;
}

.ac-thumbs {
  display: flex;
  gap: 4px;
}

.ac-thumbs img {
  width: 48px;
  height: 48px;
  object-fit: cover;
  border-radius: 4px;
  border: 1px solid var(--border);
}

.ac-prompt {
  max-width: 260px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.ac-error-cell {
  max-width: 180px;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  color: var(--red, #f87171);
}

.ac-empty {
  text-align: center;
  color: var(--text-dim);
  padding: 16px;
}

.ac-check {
  margin-left: 10px;
  font-size: 0.75rem;
}

.ac-poll-hint {
  margin-left: 8px;
  font-size: 0.7rem;
  color: var(--text-dim);
}

.ac-st-pending {
  color: var(--ochre, #d9a441);
}

.ac-st-completed {
  color: var(--cyan, #37e6d4);
}

.ac-st-failed {
  color: var(--red, #f87171);
}
</style>
