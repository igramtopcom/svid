import client from './client'
import type { ApiResponse, PaginatedResponse, Ticket, FeatureRequest, AppRating, RatingStats, FeedbackStats } from '@/types'

// Tickets
export async function listTickets(params?: {
  page?: number
  per_page?: number
  status?: string
  category?: string
  brand?: string
  device_id?: string
  search?: string
}) {
  const res = await client.get<PaginatedResponse<Ticket>>('/tickets', { params })
  return res.data.data
}

export async function getTicket(id: string) {
  const res = await client.get<ApiResponse<Ticket>>(`/tickets/${id}`)
  return res.data.data
}

export async function updateTicket(id: string, data: { status?: string }) {
  const res = await client.patch<ApiResponse<Ticket>>(`/tickets/${id}`, data)
  return res.data.data
}

export async function adminReplyTicket(id: string, message: string) {
  const res = await client.post<ApiResponse<Ticket>>(`/tickets/${id}/messages`, { content: message })
  return res.data.data
}

// Feature Requests
export async function listFeatureRequests(params?: {
  page?: number
  per_page?: number
  status?: string
  sort?: string
  brand?: string
  search?: string
}) {
  const res = await client.get<PaginatedResponse<FeatureRequest>>('/features', { params })
  return res.data.data
}

export async function getFeatureRequest(id: string) {
  const res = await client.get<ApiResponse<FeatureRequest>>(`/features/${id}`)
  return res.data.data
}

export async function updateFeatureRequest(id: string, data: { status?: string; admin_response?: string }) {
  const res = await client.patch<ApiResponse<FeatureRequest>>(`/features/${id}`, data)
  return res.data.data
}

// Ratings
export async function listRatings(params?: { page?: number; per_page?: number; rating?: string; sort?: string; brand?: string }) {
  const res = await client.get<PaginatedResponse<AppRating>>('/ratings', { params })
  return res.data.data
}

export async function getRatingStats(brand?: string) {
  const res = await client.get<ApiResponse<RatingStats>>('/ratings/stats', { params: { brand } })
  return res.data.data
}

// Feedback Stats
export async function getFeedbackStats(brand?: string) {
  const res = await client.get<ApiResponse<FeedbackStats>>('/feedback/stats', { params: { brand } })
  return res.data.data
}
