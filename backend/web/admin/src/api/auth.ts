import axios from 'axios'
import type { ApiResponse, LoginRequest, LoginResponse } from '@/types'

export async function login(data: LoginRequest): Promise<LoginResponse> {
  const res = await axios.post<ApiResponse<LoginResponse>>('/admin/v1/auth/login', data)
  return res.data.data
}
