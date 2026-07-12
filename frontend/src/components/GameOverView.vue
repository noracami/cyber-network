<script setup>
import { computed } from 'vue'
import { useRoomStore } from '../stores/room'

const room = useRoomStore()

const ranking = computed(() => room.result?.ranking || [])
</script>

<template>
  <div class="game-over">
    <div v-if="room.result" class="go-hero">
      <div class="go-trophy">🏆</div>
      <div class="go-winner">{{ room.nameOf(room.result.winner) }}</div>
      <div class="go-caption">GRID MASTER — 網域由此定名</div>
    </div>
    <h2 v-else>🏁 遊戲結束</h2>

    <table class="ranking">
      <thead>
        <tr>
          <th>#</th>
          <th>玩家</th>
          <th>供電節點</th>
          <th>能量點數</th>
          <th>佔據節點</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="(row, index) in ranking" :key="row.player" :class="{ self: row.player === room.selfId }">
          <td><span class="rank-badge" :class="`rank-${index + 1}`">{{ index + 1 }}</span></td>
          <td>{{ room.nameOf(row.player) }}</td>
          <td>{{ row.powered }}</td>
          <td>{{ row.credits }}</td>
          <td>{{ row.cities }}</td>
        </tr>
      </tbody>
    </table>

    <button class="btn primary" @click="room.backToLobby()">回到大廳</button>
  </div>
</template>
