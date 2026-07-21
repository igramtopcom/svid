import { useBrandStore } from '@/store/brand'

export default function BrandBadge() {
  const brand = useBrandStore((s) => s.brand)
  if (!brand) return null

  return (
    <span className="ml-2 text-xs font-medium px-2 py-0.5 rounded-full bg-brand-50 text-brand-600 capitalize">
      {brand === 'vidcombo' ? 'VidCombo' : brand.toUpperCase()}
    </span>
  )
}
