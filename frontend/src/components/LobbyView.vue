<script setup>
import { computed } from 'vue'
import { useRoomStore } from '../stores/room'

const room = useRoomStore()

const MAX_SEATS = 6

const seatCards = computed(() => {
  const filled = room.seats.map((id) => ({ id, ...room.users[id] }))
  return [...filled, ...Array(Math.max(0, MAX_SEATS - filled.length)).fill(null)]
})

const isGuest = computed(() => !room.self || room.self.role === 'guest')
</script>

<template>
  <div class="lobby">
    <h2>
      等待開始
      <span class="hint">{{ room.seats.length }}/{{ MAX_SEATS }} 位玩家</span>
    </h2>

    <div class="seats">
      <div
        v-for="(seat, index) in seatCards"
        :key="seat ? seat.id : `empty-${index}`"
        class="seat"
        :class="{
          filled: seat,
          ready: seat?.ready,
          offline: seat && !seat.online,
          self: seat?.id === room.selfId,
        }"
      >
        <template v-if="seat">
          <img v-if="seat.avatar" :src="seat.avatar" class="avatar" alt="" />
          <div class="seat-name">{{ seat.name }}</div>
          <div class="seat-badge">
            {{ seat.ready ? '✔ 已準備' : '等待中' }}<span v-if="!seat.online">・離線</span>
          </div>
        </template>
        <template v-else>
          <a v-if="isGuest" class="btn ghost" href="/auth/discord">登入後入座</a>
          <button v-else-if="!room.seated" class="btn ghost" @click="room.seatTake()">入座</button>
          <span v-else class="seat-empty">空位</span>
        </template>
      </div>
    </div>

    <div class="lobby-actions">
      <template v-if="room.seated">
        <button v-if="!room.self?.ready" class="btn primary" @click="room.ready()">準備</button>
        <button v-else class="btn ghost" @click="room.unready()">取消準備</button>
        <button class="btn ghost" @click="room.seatLeave()">離座</button>
        <button class="btn primary" :disabled="!room.allReady" @click="room.gameStart()">
          開始遊戲
        </button>
      </template>
      <p v-else-if="isGuest" class="hint">用 Discord 登入即可入座；旁觀和聊天不需要登入。</p>
      <p v-else class="hint">點「入座」加入牌局；不入座也可以旁觀和聊天。</p>
    </div>

    <p v-if="room.spectators.length" class="spectators">
      旁觀者：
      <span v-for="spectator in room.spectators" :key="spectator.id" class="spectator-name">
        {{ spectator.name }}
      </span>
    </p>
  </div>
</template>
