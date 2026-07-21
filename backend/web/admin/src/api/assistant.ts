import client from './client'
import type { ApiResponse, PaginatedResponse, ChatSession, KnowledgeBase, AssistantStats } from '@/types'

// Sessions
export async function listSessions(params?: { page?: number; per_page?: number; status?: string; brand?: string }) {
  const res = await client.get<PaginatedResponse<ChatSession>>('/assistant/sessions', { params })
  return res.data.data
}

export async function getSession(id: string) {
  const res = await client.get<ApiResponse<ChatSession>>(`/assistant/sessions/${id}`)
  return res.data.data
}

// Knowledge Base
export async function listKnowledge(params?: { page?: number; per_page?: number; category?: string }) {
  const res = await client.get<PaginatedResponse<KnowledgeBase>>('/assistant/knowledge', { params })
  return res.data.data
}

export async function getKnowledge(id: string) {
  const res = await client.get<ApiResponse<KnowledgeBase>>(`/assistant/knowledge/${id}`)
  return res.data.data
}

export async function createKnowledge(data: Partial<KnowledgeBase>) {
  const res = await client.post<ApiResponse<KnowledgeBase>>('/assistant/knowledge', data)
  return res.data.data
}

export async function updateKnowledge(id: string, data: Partial<KnowledgeBase>) {
  const res = await client.patch<ApiResponse<KnowledgeBase>>(`/assistant/knowledge/${id}`, data)
  return res.data.data
}

export async function deleteKnowledge(id: string) {
  await client.delete(`/assistant/knowledge/${id}`)
}

// Stats
export async function getAssistantStats(brand?: string) {
  const res = await client.get<ApiResponse<AssistantStats>>('/assistant/stats', { params: { brand } })
  return res.data.data
}
