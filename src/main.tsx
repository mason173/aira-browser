import { createRoot } from "react-dom/client";
import { ThemeProvider } from "next-themes";
import App from "@/App";
import "./index.css";
import i18n, { i18nReady } from "./i18n";

function toDocumentLanguage(language: string) {
  const normalized = String(language || "").trim().toLowerCase();
  if (normalized.startsWith("zh")) return "zh-CN";
  return "en";
}

function syncDocumentLanguage(language: string) {
  const resolvedLanguage = toDocumentLanguage(language);
  document.documentElement.lang = resolvedLanguage;
  document.body.lang = resolvedLanguage;
}

await i18nReady;
syncDocumentLanguage(i18n.language);
i18n.on("languageChanged", syncDocumentLanguage);

createRoot(document.getElementById("root")!).render(
  <ThemeProvider attribute="class" defaultTheme="system" enableSystem>
    <App />
  </ThemeProvider>,
);
