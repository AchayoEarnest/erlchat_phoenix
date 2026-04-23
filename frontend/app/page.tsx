// app/page.tsx
// Root route — redirect to /chat if already authenticated, otherwise /auth/login
import { redirect } from 'next/navigation';

export default function RootPage() {
  // Server-side: always send to login. The chat page handles its own
  // auth check and redirects back if a valid token exists in the store.
  redirect('/auth/login');
}
