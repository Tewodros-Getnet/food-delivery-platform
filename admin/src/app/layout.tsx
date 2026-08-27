import type { Metadata } from 'next';
import Script from 'next/script';
import './globals.css';
import { ThemeProvider } from '@/components/ThemeProvider';

export const metadata: Metadata = {
  title: 'Food Delivery Admin',
  description: 'Admin Dashboard',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" suppressHydrationWarning>
      <body className="bg-gray-50 dark:bg-gray-950 text-gray-900 dark:text-gray-100">
        {/*
          Runs synchronously before React hydrates — reads localStorage and
          adds 'dark' to <html> if needed, preventing the white flash.
          'beforeInteractive' is the only strategy that runs before hydration.
        */}
        <Script id="theme-init" strategy="beforeInteractive">{`
          try {
            if (localStorage.getItem('admin-theme') === 'dark') {
              document.documentElement.classList.add('dark');
            }
          } catch (_) {}
        `}</Script>
        <ThemeProvider>{children}</ThemeProvider>
      </body>
    </html>
  );
}
