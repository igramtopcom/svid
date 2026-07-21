import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { listAdmins, createAdmin, updateAdmin, deleteAdmin } from '@/api/system'
import { SkeletonTable } from '@/components/common/LoadingSpinner'
import EmptyState from '@/components/common/EmptyState'
import { formatDate } from '@/lib/utils'

export default function AdminUsers() {
  const queryClient = useQueryClient()
  const [showCreate, setShowCreate] = useState(false)
  const [editId, setEditId] = useState<string | null>(null)
  const [form, setForm] = useState({ email: '', password: '', name: '', brand_scope: '' })
  const [editForm, setEditForm] = useState({ name: '', password: '', brand_scope: '' })

  const { data: admins, isLoading } = useQuery({
    queryKey: ['admins'],
    queryFn: listAdmins,
  })

  const createMutation = useMutation({
    mutationFn: () => createAdmin({
      email: form.email,
      password: form.password,
      name: form.name,
      brand_scope: form.brand_scope || undefined,
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admins'] })
      setShowCreate(false)
      setForm({ email: '', password: '', name: '', brand_scope: '' })
      toast.success('Admin created')
    },
  })

  const updateMutation = useMutation({
    mutationFn: () => updateAdmin(editId!, {
      name: editForm.name || undefined,
      password: editForm.password || undefined,
      brand_scope: editForm.brand_scope,
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admins'] })
      setEditId(null)
      toast.success('Admin updated')
    },
  })

  const deleteMutation = useMutation({
    mutationFn: (id: string) => deleteAdmin(id),
    onSuccess: () => { queryClient.invalidateQueries({ queryKey: ['admins'] }); toast.success('Admin deleted') },
  })

  if (isLoading) return <SkeletonTable rows={3} />

  return (
    <div>
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-xl font-bold">Admin Users</h2>
        <button onClick={() => setShowCreate(!showCreate)}
          className="px-4 py-2 bg-brand-600 text-white rounded-lg text-sm hover:bg-brand-700">
          {showCreate ? 'Cancel' : 'Add Admin'}
        </button>
      </div>

      {/* Create Form */}
      {showCreate && (
        <div className="bg-white rounded-lg border border-gray-200 p-5 mb-4">
          <div className="grid grid-cols-4 gap-4">
            <input type="text" placeholder="Name" value={form.name}
              onChange={(e) => setForm({ ...form, name: e.target.value })}
              className="px-3 py-2 border border-gray-300 rounded-md text-sm" />
            <input type="email" placeholder="Email" value={form.email}
              onChange={(e) => setForm({ ...form, email: e.target.value })}
              className="px-3 py-2 border border-gray-300 rounded-md text-sm" />
            <input type="password" placeholder="Password (min 8)" value={form.password}
              onChange={(e) => setForm({ ...form, password: e.target.value })}
              className="px-3 py-2 border border-gray-300 rounded-md text-sm" />
            <select value={form.brand_scope}
              onChange={(e) => setForm({ ...form, brand_scope: e.target.value })}
              className="px-3 py-2 border border-gray-300 rounded-md text-sm">
              <option value="">Super Admin (all brands)</option>
              <option value="ssvid">SSvid only</option>
              <option value="vidcombo">VidCombo only</option>
            </select>
          </div>
          <button onClick={() => createMutation.mutate()} disabled={createMutation.isPending || !form.email || !form.password || !form.name}
            className="mt-3 px-4 py-2 bg-brand-600 text-white rounded-lg text-sm hover:bg-brand-700 disabled:opacity-50">
            {createMutation.isPending ? 'Creating...' : 'Create Admin'}
          </button>
        </div>
      )}

      {!admins?.length ? <EmptyState message="No admins" /> : (
        <div className="bg-white rounded-lg border border-gray-200 overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="bg-gray-50 border-b">
                <th className="text-left px-4 py-3 font-medium text-gray-600">Name</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Email</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Brand Scope</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Created</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Last Login</th>
                <th className="text-left px-4 py-3 font-medium text-gray-600">Actions</th>
              </tr>
            </thead>
            <tbody>
              {admins.map((admin) => (
                <tr key={admin.id} className="border-b last:border-0">
                  <td className="px-4 py-3">
                    {editId === admin.id ? (
                      <input type="text" value={editForm.name} onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
                        className="px-2 py-1 border border-gray-300 rounded text-sm w-full" />
                    ) : admin.name}
                  </td>
                  <td className="px-4 py-3 text-gray-600">{admin.email}</td>
                  <td className="px-4 py-3">
                    {editId === admin.id ? (
                      <select value={editForm.brand_scope}
                        onChange={(e) => setEditForm({ ...editForm, brand_scope: e.target.value })}
                        className="px-2 py-1 border border-gray-300 rounded text-sm">
                        <option value="">Super Admin</option>
                        <option value="ssvid">SSvid</option>
                        <option value="vidcombo">VidCombo</option>
                      </select>
                    ) : (
                      <span className={`inline-block px-2 py-0.5 rounded-full text-xs font-medium ${
                        admin.brand_scope === 'ssvid' ? 'bg-red-100 text-red-700' :
                        admin.brand_scope === 'vidcombo' ? 'bg-blue-100 text-blue-700' :
                        'bg-gray-100 text-gray-700'
                      }`}>
                        {admin.brand_scope || 'Super Admin'}
                      </span>
                    )}
                  </td>
                  <td className="px-4 py-3 text-gray-500">{formatDate(admin.created_at)}</td>
                  <td className="px-4 py-3 text-gray-500">{admin.last_login_at ? formatDate(admin.last_login_at) : 'Never'}</td>
                  <td className="px-4 py-3">
                    {editId === admin.id ? (
                      <div className="flex gap-2">
                        <input type="password" placeholder="New password" value={editForm.password}
                          onChange={(e) => setEditForm({ ...editForm, password: e.target.value })}
                          className="px-2 py-1 border border-gray-300 rounded text-xs w-28" />
                        <button onClick={() => updateMutation.mutate()} disabled={updateMutation.isPending}
                          className="text-xs text-green-600 hover:underline">Save</button>
                        <button onClick={() => setEditId(null)} className="text-xs text-gray-500 hover:underline">Cancel</button>
                      </div>
                    ) : (
                      <div className="flex gap-2">
                        <button onClick={() => { setEditId(admin.id); setEditForm({ name: admin.name, password: '', brand_scope: admin.brand_scope || '' }) }}
                          className="text-xs text-indigo-600 hover:underline">Edit</button>
                        <button onClick={() => { if (confirm(`Delete admin ${admin.email}?`)) deleteMutation.mutate(admin.id) }}
                          className="text-xs text-red-600 hover:underline">Delete</button>
                      </div>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
