import { create } from 'zustand'
import type { AdminInfo } from '@/types'
import { useBrandStore } from '@/store/brand'

interface AuthState {
  token: string | null
  admin: AdminInfo | null
  setAuth: (token: string, admin: AdminInfo) => void
  logout: () => void
  isAuthenticated: () => boolean
}

function safeParseAdmin(): AdminInfo | null {
  try {
    return JSON.parse(localStorage.getItem('admin_info') || 'null')
  } catch {
    localStorage.removeItem('admin_info')
    return null
  }
}

export const useAuthStore = create<AuthState>((set, get) => ({
  token: localStorage.getItem('admin_token'),
  admin: safeParseAdmin(),

  setAuth: (token: string, admin: AdminInfo) => {
    localStorage.setItem('admin_token', token)
    localStorage.setItem('admin_info', JSON.stringify(admin))
    set({ token, admin })
    // Sync brand store with admin's brand_scope
    if (admin.brand_scope) {
      useBrandStore.getState().setBrand(admin.brand_scope)
    }
  },

  logout: () => {
    localStorage.removeItem('admin_token')
    localStorage.removeItem('admin_info')
    set({ token: null, admin: null })
    useBrandStore.getState().setBrand('')
  },

  isAuthenticated: () => !!get().token,
}))
