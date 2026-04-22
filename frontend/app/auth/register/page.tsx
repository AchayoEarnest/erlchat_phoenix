// app/auth/register/page.tsx
'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { api } from '@/services/api';
import { useAuthStore } from '@/store/chat';
import { wsService } from '@/services/phoenix-socket';
import toast from 'react-hot-toast';

export default function RegisterPage() {
  const router = useRouter();
  const { setAuth } = useAuthStore();
  const [form, setForm] = useState({ username: '', email: '', password: '', confirm: '' });
  const [isLoading, setIsLoading] = useState(false);

  const update = (key: string) => (e: React.ChangeEvent<HTMLInputElement>) =>
    setForm(f => ({ ...f, [key]: e.target.value }));

  const handleRegister = async (e: React.FormEvent) => {
    e.preventDefault();
    if (form.password !== form.confirm) {
      toast.error("Passwords don't match");
      return;
    }
    setIsLoading(true);
    try {
      const { user, tokens } = await api.register(form.username, form.email, form.password);
      setAuth(user, tokens.access_token, tokens.refresh_token);
      localStorage.setItem('access_token', tokens.access_token);
      localStorage.setItem('refresh_token', tokens.refresh_token);
      await wsService.connect(tokens.access_token);
      toast.success('Welcome to ErlChat! 🎉');
      router.push('/chat');
    } catch (err: unknown) {
      const msg = (err as { response?: { data?: { error?: string } } })?.response?.data?.error || 'Registration failed';
      toast.error(msg);
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-950 px-4">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <div className="w-12 h-12 rounded-xl bg-indigo-600 flex items-center justify-center mx-auto mb-3">
            <svg className="w-7 h-7 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2}
                d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
            </svg>
          </div>
          <h1 className="text-2xl font-bold text-gray-100">Create your account</h1>
          <p className="text-gray-500 text-sm mt-1">Join ErlChat today</p>
        </div>

        <form onSubmit={handleRegister} className="space-y-4">
          {[
            { key: 'username', label: 'Username', type: 'text', placeholder: 'johndoe', auto: 'username' },
            { key: 'email',    label: 'Email',    type: 'email', placeholder: 'you@example.com', auto: 'email' },
            { key: 'password', label: 'Password', type: 'password', placeholder: '••••••••', auto: 'new-password' },
            { key: 'confirm',  label: 'Confirm password', type: 'password', placeholder: '••••••••', auto: 'new-password' },
          ].map(f => (
            <div key={f.key}>
              <label className="block text-xs font-medium text-gray-400 mb-1.5">{f.label}</label>
              <input
                type={f.type}
                value={form[f.key as keyof typeof form]}
                onChange={update(f.key)}
                placeholder={f.placeholder}
                className="input-field w-full"
                autoComplete={f.auto}
                required
              />
            </div>
          ))}

          <button
            type="submit"
            disabled={isLoading}
            className="btn-primary w-full py-2.5 disabled:opacity-60 flex items-center justify-center gap-2"
          >
            {isLoading && <div className="w-4 h-4 border-2 border-white/30 border-t-white rounded-full animate-spin" />}
            {isLoading ? 'Creating account…' : 'Create account'}
          </button>
        </form>

        <p className="text-center text-sm text-gray-500 mt-6">
          Already have an account?{' '}
          <Link href="/auth/login" className="text-indigo-400 hover:text-indigo-300">
            Sign in
          </Link>
        </p>
      </div>
    </div>
  );
}
