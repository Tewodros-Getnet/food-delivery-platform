'use client';
import { createContext, useContext, useEffect, useState } from 'react';

type Theme = 'light' | 'dark';

const ThemeContext = createContext<{ theme: Theme; toggle: () => void }>({
  theme: 'light',
  toggle: () => {},
});

export function ThemeProvider({ children }: { children: React.ReactNode }) {
  const [theme, setTheme] = useState<Theme>('light');

  // Sync React state with whatever the inline script already applied to <html>.
  // We read localStorage once on mount — no flash because the class is already set.
  useEffect(() => {
    const stored = localStorage.getItem('admin-theme');
    if (stored === 'dark') setTheme('dark');
  }, []);

  const toggle = () => {
    const next = theme === 'dark' ? 'light' : 'dark';
    setTheme(next);
    localStorage.setItem('admin-theme', next);
    document.documentElement.classList.toggle('dark', next === 'dark');
  };

  // Always render the Provider — never skip it.
  // The initial theme value is 'light' which matches the server render.
  // suppressHydrationWarning on <html> handles the class mismatch.
  return (
    <ThemeContext.Provider value={{ theme, toggle }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() {
  return useContext(ThemeContext);
}
