// R2 多房間 E2E：開新房間 → 分房開局；main 與分房並行互不干擾；
// 房間列表可見可加入；聊天隔離；房號連結直達；壞 hash 退回 main。
import { chromium } from 'playwright'

const API = process.env.API_URL || 'http://localhost:4000'
const APP = process.env.APP_URL || 'http://localhost:5173'

async function register(prefix) {
  const username = `${prefix}${Date.now() % 100000}`
  const res = await fetch(`${API}/api/auth/register`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username, password: 'test1234' }),
  })
  if (!res.ok) throw new Error(`register failed: ${res.status} ${await res.text()}`)
  return res.json() // { token, name }
}

const browser = await chromium.launch()
const errors = []

async function newPage(auth) {
  const context = await browser.newContext()
  const page = await context.newPage()
  page.on('pageerror', (e) => errors.push(String(e)))
  await page.addInitScript(
    ([t, n]) => {
      localStorage.setItem('gm_password_token', t)
      localStorage.setItem('gm_name', n)
    },
    [auth.token, auth.name],
  )
  return page
}

const userA = await register('rma')
const userB = await register('rmb')

// ── A：main 開新房間 → 分房開局 ─────────────────────────
const pageA = await newPage(userA)
await pageA.goto(APP)
await pageA.getByRole('button', { name: '＋開新房間' }).click()
await pageA.waitForURL(/#\/r\/[a-z0-9]{4,6}$/)
const roomCode = pageA.url().match(/#\/r\/([a-z0-9]{4,6})$/)[1]
console.log(`room code: ${roomCode}`)

// 分房 chip：房號＋複製連結＋回大廳
await pageA.getByText(`#${roomCode}`).first().waitFor({ timeout: 5000 })
await pageA.getByRole('button', { name: /複製連結/ }).waitFor()
await pageA.getByRole('button', { name: '回大廳' }).waitFor()

await pageA.getByRole('button', { name: '入座' }).first().click()
await pageA.getByRole('button', { name: '＋ NPC' }).click()
await pageA.getByRole('button', { name: /^準備$/ }).click()
await pageA.getByRole('button', { name: '開始遊戲' }).click()
await pageA.getByRole('button', { name: '結束遊戲' }).waitFor({ timeout: 10000 })
console.log('phase A OK: sub-room in game')

// ── B：main 不受影響、房間列表看得到分房 ────────────────
const pageB = await newPage(userB)
await pageB.goto(APP)
// main 還在大廳（雙房並行互不干擾）
await pageB.getByText('等待開始').waitFor({ timeout: 5000 })
// 房間列表出現 A 的分房、標示對戰中（30s 輪詢之外，掛載即抓一次）
await pageB
  .getByRole('button', { name: new RegExp(`#${roomCode} 對戰中`) })
  .waitFor({ timeout: 10000 })

// main 發話 → 不會漏進分房（main 聊天歷史跨執行保留，訊息帶唯一後綴）
const secret = `main 的悄悄話 ${Date.now() % 100000}`
await pageB.getByPlaceholder('輸入訊息…').fill(secret)
await pageB.getByRole('button', { name: '送出' }).click()
await pageB.getByText(secret).waitFor()
console.log('phase B OK: main lobby intact, room list shows sub-room')

// ── B 點列表加入分房：旁觀 in_game、聊天隔離 ────────────
await pageB.getByRole('button', { name: new RegExp(`#${roomCode}`) }).click()
await pageB.waitForURL(new RegExp(`#/r/${roomCode}$`))
await pageB.getByText('遊戲開始！').first().waitFor({ timeout: 5000 })
await pageB.getByText('伏特').first().waitFor({ timeout: 5000 })
if (await pageB.getByText(secret).count()) {
  throw new Error('聊天洩漏：main 的訊息出現在分房')
}
console.log('phase C OK: joined sub-room via list, chat isolated')

// A 那頭看到 B 進場後，回大廳也要乾淨
await pageA.screenshot({ path: '/tmp/rooms-subroom-a.png', fullPage: true })
await pageB.screenshot({ path: '/tmp/rooms-subroom-b.png', fullPage: true })

// ── 房號連結直達＋壞 hash 退回 main ─────────────────────
const pageC = await newPage(userB)
await pageC.goto(`${APP}/#/r/${roomCode}`)
await pageC.getByText(`#${roomCode}`).first().waitFor({ timeout: 5000 })
await pageC.getByText('伏特').first().waitFor({ timeout: 10000 })

const pageD = await newPage(userA)
await pageD.goto(`${APP}/#/r/BAD!!`)
await pageD.getByText('等待開始').waitFor({ timeout: 5000 })
console.log('phase D OK: direct link works, bad hash falls back to main')

// ── A 回大廳：main 大廳畫面＋房間列表仍列分房 ───────────
await pageA.getByRole('button', { name: '回大廳' }).click()
await pageA.getByText('等待開始').waitFor({ timeout: 5000 })
await pageA
  .getByRole('button', { name: new RegExp(`#${roomCode} 對戰中`) })
  .waitFor({ timeout: 10000 })
await pageA.screenshot({ path: '/tmp/rooms-main-a.png', fullPage: true })
console.log('phase E OK: back to main, room list still shows sub-room')

if (errors.length) throw new Error('pageerror: ' + errors.join('\n'))
console.log('ALL OK')
await browser.close()
