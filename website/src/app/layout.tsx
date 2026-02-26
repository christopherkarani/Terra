import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Terra | On-Device GenAI Observability",
  description: "Privacy-first observability for on-device GenAI apps in Swift. Built on OpenTelemetry.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body className="antialiased">
        {children}
      </body>
    </html>
  );
}
