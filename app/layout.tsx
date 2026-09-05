import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Betslip Pro",
  description: "Tanzania's sports prediction marketplace",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="sw">
      <body>{children}</body>
    </html>
  );
}
