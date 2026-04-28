import AuthGuard from '@/components/AuthGuard';
import Sidebar from '@/components/Sidebar';
import RealtimeNotifications from '@/components/RealtimeNotifications';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  return (
    <AuthGuard>
      <div className="flex min-h-screen">
        <Sidebar />
        <div className="flex-1 flex flex-col overflow-auto">
          <div className="flex justify-end px-6 pt-4">
            <RealtimeNotifications />
          </div>
          <main className="flex-1 px-6 pb-6">{children}</main>
        </div>
      </div>
    </AuthGuard>
  );
}
