import type { Config } from 'tailwindcss';

const config: Config = {
  // 'class' strategy: dark mode activates only when the <html> element
  // has the 'dark' class. Nothing changes automatically based on OS preference.
  // This is the safest approach — zero risk of unexpected visual changes.
  darkMode: 'class',
  content: ['./src/**/*.{js,ts,jsx,tsx,mdx}'],
  theme: { extend: {} },
  plugins: [],
};
export default config;
