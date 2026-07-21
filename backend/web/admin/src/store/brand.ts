import { create } from 'zustand'
import { persist } from 'zustand/middleware'

interface BrandState {
  brand: string // '' = all brands, 'ssvid', 'vidcombo'
  setBrand: (brand: string) => void
}

export const useBrandStore = create<BrandState>()(
  persist(
    (set) => ({
      brand: '',
      setBrand: (brand) => set({ brand }),
    }),
    { name: 'admin-brand-filter' }
  )
)

// Sync brand selection to DOM for CSS custom property theming
useBrandStore.subscribe((state) => {
  document.documentElement.dataset.brand = state.brand || 'all'
})
// Set initial value on load
document.documentElement.dataset.brand = useBrandStore.getState().brand || 'all'
