// R3 行動版驗收：iPhone 14 級（390×844 直向）模擬。
// 第一段：?demo 七場景逐一截圖＋橫向溢位量測（假資料涵蓋所有階段畫面）。
// 第二段：真實流程 smoke——註冊→開分房→入座＋NPC→開局→聊天摺疊展開→規則 modal。
import { chromium, devices } from 'playwright'

const API = process.env.API_URL || 'http://localhost:4000'
const APP = process.env.APP_URL || 'http://localhost:5173'
const iphone = devices['iPhone 14']

const browser = await chromium.launch()
const errors = []

async function newPage(auth = null) {
  const context = await browser.newContext({ ...iphone })
  const page = await context.newPage()
  page.on('pageerror', (e) => errors.push(String(e)))
  if (auth) {
    await page.addInitScript(
      ([t, n]) => {
        localStorage.setItem('gm_password_token', t)
        localStorage.setItem('gm_name', n)
      },
      [auth.token, auth.name],
    )
  }
  return page
}

/** 橫向溢位量測：html/body scrollWidth 不得超過 viewport，超了就找出元兇 */
async function assertNoHOverflow(page, label) {
  const result = await page.evaluate(() => {
    const vw = document.documentElement.clientWidth
    const sw = Math.max(document.documentElement.scrollWidth, document.body.scrollWidth)
    if (sw <= vw + 1) return { ok: true, vw, sw }
    const wide = []
    for (const el of document.querySelectorAll('*')) {
      const r = el.getBoundingClientRect()
      if (r.right > vw + 1 && r.width > 40) {
        wide.push(`${el.tagName}.${[...el.classList].join('.')} right=${Math.round(r.right)}`)
      }
      if (wide.length >= 8) break
    }
    return { ok: false, vw, sw, wide }
  })
  if (!result.ok) {
    throw new Error(`${label} 橫向溢位: vw=${result.vw} sw=${result.sw}\n${result.wide.join('\n')}`)
  }
  console.log(`${label}: no h-overflow (vw=${result.vw})`)
}

// ── 第一段：demo 七場景 ─────────────────────────────────
const SCENARIOS = ['auction', 'bidding', 'discard', 'resources', 'building', 'bureaucracy', 'game_over']
const demoPage = await newPage()
await demoPage.goto(`${APP}/?demo`)
await demoPage.waitForTimeout(2500) // 地圖初始化

for (const key of SCENARIOS) {
  const idx = SCENARIOS.indexOf(key)
  await demoPage.locator('.demo-bar .tab').nth(idx).click()
  await demoPage.waitForTimeout(800)
  await assertNoHOverflow(demoPage, `demo:${key}`)
  await demoPage.screenshot({ path: `/tmp/m-${key}.png`, fullPage: true })
}
console.log('phase 1 OK: demo scenarios captured')

// ── 第二段：真實流程 smoke ──────────────────────────────
const username = `mob${Date.now() % 100000}`
const res = await fetch(`${API}/api/auth/register`, {
  method: 'POST',
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify({ username, password: 'test1234' }),
})
if (!res.ok) throw new Error(`register failed: ${res.status}`)
const auth = await res.json()

const page = await newPage(auth)
await page.goto(APP)
await page.getByText('等待開始').waitFor({ timeout: 8000 })
await assertNoHOverflow(page, 'main-lobby')
await page.screenshot({ path: '/tmp/m-lobby.png', fullPage: true })

// 開分房 → 入座 → NPC → 開局
await page.getByRole('button', { name: '＋開新房間' }).click()
await page.waitForURL(/#\/r\/[a-z0-9]{4,6}$/)
await page.getByRole('button', { name: '入座' }).first().tap()
await page.getByRole('button', { name: '＋ NPC' }).tap()
await page.getByRole('button', { name: /^準備$/ }).tap()
await page.getByRole('button', { name: '開始遊戲' }).tap()
await page.getByText('競標設施').first().waitFor({ timeout: 10000 })
await page.waitForTimeout(2000)
await assertNoHOverflow(page, 'in-game')
await page.screenshot({ path: '/tmp/m-game.png', fullPage: true })

// 聊天摺疊：預設收合，展開發話
await page.locator('.chat .collapse-head').tap()
await page.getByPlaceholder('輸入訊息…').fill('手機打字測試')
await page.getByRole('button', { name: '送出' }).tap()
await page.getByText('手機打字測試').waitFor({ timeout: 5000 })
await page.screenshot({ path: '/tmp/m-chat.png', fullPage: true })

// 規則 modal 全幅
await page.getByRole('button', { name: /規則/ }).tap()
await page.waitForTimeout(500)
await assertNoHOverflow(page, 'rules-modal')
await page.screenshot({ path: '/tmp/m-rules.png' })

if (errors.length) throw new Error('pageerror: ' + errors.join('\n'))
console.log('ALL OK')
await browser.close()
