// R1 持久化 E2E 第一段：註冊 → 入座 → ＋NPC → 開局 → 等 NPC 出手 → 存身份供第二段用
import { chromium } from 'playwright'
import { writeFileSync } from 'node:fs'

const API = process.env.API_URL || 'http://localhost:4000'
const APP = process.env.APP_URL || 'http://localhost:5173'

const username = `persist${Date.now() % 100000}`
const res = await fetch(`${API}/api/auth/register`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ username, password: 'test1234' }),
})
if (!res.ok) throw new Error(`register failed: ${res.status} ${await res.text()}`)
const { token, name } = await res.json()

const browser = await chromium.launch()
const page = await browser.newPage()
const errors = []
page.on('pageerror', (e) => errors.push(String(e)))

await page.addInitScript(
  ([t, n]) => {
    localStorage.setItem('gm_password_token', t)
    localStorage.setItem('gm_name', n)
  },
  [token, name],
)

await page.goto(APP)
await page.getByRole('button', { name: '入座' }).first().click()
await page.getByRole('button', { name: '＋ NPC' }).click()
await page.getByRole('button', { name: /^準備$/ }).click()
await page.getByRole('button', { name: '開始遊戲' }).click()

// 進入遊戲（入座玩家看得到「結束遊戲」鈕）＋ NPC（伏特）出手
await page.getByRole('button', { name: '結束遊戲' }).waitFor({ timeout: 10000 })
await page.getByText('伏特').first().waitFor({ timeout: 15000 })
await page.waitForTimeout(2500) // 讓 NPC 多動幾手

await page.screenshot({ path: '/tmp/persist-before.png', fullPage: true })
writeFileSync('/tmp/persist-session.json', JSON.stringify({ token, name, username }))

if (errors.length) throw new Error('pageerror: ' + errors.join('\n'))
console.log(`phase1 OK: ${username} in game, NPC active`)
await browser.close()
