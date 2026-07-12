<script setup>
import { computed, ref } from 'vue'
import { reconnect } from '../channels/socket'
import { useSettingsStore } from '../stores/settings'
import { useUiStore } from '../stores/ui'

const ui = useUiStore()
const settings = useSettingsStore()

/** @type {import('vue').Ref<'login' | 'register'>} */
const mode = ref('login')
const username = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)

const USERNAME_RE = /^[a-zA-Z0-9]{3,20}$/

const clientError = computed(() => {
  if (!username.value || !password.value) return null
  if (!USERNAME_RE.test(username.value)) return '帳號須為 3–20 個英數字元'
  if (password.value.length < 4) return '密碼至少 4 個字元'
  return null
})

const canSubmit = computed(
  () => !busy.value && username.value !== '' && password.value !== '' && clientError.value === null
)

function switchMode(next) {
  mode.value = next
  error.value = ''
}

async function submit() {
  if (!canSubmit.value) return
  busy.value = true
  error.value = ''
  try {
    const resp = await fetch(`/api/auth/${mode.value}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username: username.value, password: password.value }),
    })
    const body = await resp.json()
    if (!resp.ok) {
      error.value = body.error || '發生錯誤，請再試一次'
      return
    }
    settings.setPasswordToken(body.token)
    ui.closeLogin()
    username.value = ''
    password.value = ''
    reconnect()
  } catch {
    error.value = '無法連線到伺服器'
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <div v-if="ui.loginOpen" class="modal-mask" @click.self="ui.closeLogin()">
    <div class="modal-box login-modal">
      <div class="rules-head">
        <h3>{{ mode === 'login' ? '登入' : '註冊' }}</h3>
        <button class="modal-close" @click="ui.closeLogin()">✕</button>
      </div>

      <div class="rules-tabs">
        <button class="tab" :class="{ active: mode === 'login' }" @click="switchMode('login')">登入</button>
        <button class="tab" :class="{ active: mode === 'register' }" @click="switchMode('register')">註冊</button>
      </div>

      <form class="login-form" @submit.prevent="submit">
        <label>
          帳號
          <input
            v-model.trim="username"
            type="text"
            autocomplete="username"
            placeholder="3–20 個英數字元"
            maxlength="20"
          />
        </label>
        <label>
          密碼
          <input
            v-model="password"
            type="password"
            :autocomplete="mode === 'login' ? 'current-password' : 'new-password'"
            placeholder="至少 4 個字元"
            maxlength="72"
          />
        </label>

        <p v-if="clientError" class="hint">{{ clientError }}</p>
        <p v-else-if="error" class="error">{{ error }}</p>

        <button class="btn primary" type="submit" :disabled="!canSubmit">
          {{ busy ? '處理中…' : mode === 'login' ? '登入' : '註冊並登入' }}
        </button>

        <p class="hint">
          測試用輕量帳號：無 email、無法找回密碼——<strong>請勿使用你在其他服務的密碼</strong>。
        </p>
      </form>
    </div>
  </div>
</template>
