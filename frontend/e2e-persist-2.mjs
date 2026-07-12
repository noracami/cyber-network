// R1 持久化 E2E 第二段：後端已重啟——同身份回來，牌局必須還在且聊天歷史完整
import { chromium } from 'playwright'
import { readFileSync } from 'node:fs'

const APP = process.env.APP_URL || 'http://localhost:5173'
const { token, name } = JSON.parse(readFileSync('/tmp/persist-session.json', 'utf8'))

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

// 還原驗證：仍在牌局中（結束遊戲鈕）、重啟前的聊天歷史還在
await page.getByRole('button', { name: '結束遊戲' }).waitFor({ timeout: 10000 })
await page.getByText('遊戲開始！').first().waitFor({ timeout: 5000 })
await page.getByText(`${name} 入座`).first().waitFor({ timeout: 5000 })

await page.waitForTimeout(1500)
await page.screenshot({ path: '/tmp/persist-after.png', fullPage: true })

if (errors.length) throw new Error('pageerror: ' + errors.join('\n'))
console.log('phase2 OK: game restored after backend restart, chat history intact')
await browser.close()
