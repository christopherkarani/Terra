"use client";

import React from 'react';
import { CodeBlock } from '@/components/CodeBlock';
import { FeatureCard } from '@/components/FeatureCard';

export default function LandingPage() {
  return (
    <div className="min-h-screen bg-[#0E1015] text-white selection:bg-cyan-500/30">
      <div className="absolute inset-0 grid-bg opacity-10 pointer-events-none" />
      <div className="absolute inset-0 hero-gradient pointer-events-none" />

      {/* Nav */}
      <nav className="relative z-10 flex items-center justify-between px-6 py-4 border-b border-white/5 backdrop-blur-md bg-black/10">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-indigo-500 flex items-center justify-center text-white font-black text-xs">T</div>
          <span className="text-xl font-extrabold tracking-tighter">Terra</span>
        </div>
        <div className="hidden md:flex gap-8 text-sm font-medium text-gray-400">
          <a href="#documentation" className="hover:text-cyan-400 transition-colors">Documentation</a>
          <a href="https://christopherkarani.github.io/Terra/docc/documentation/terra/" className="hover:text-cyan-400 transition-colors">DocC API</a>
          <a href="https://github.com/christopherkarani/Terra" className="hover:text-cyan-400 transition-colors">GitHub</a>
          <a href="https://github.com/christopherkarani/Terra/blob/main/Docs/Integrations.md" className="hover:text-cyan-400 transition-colors">Integrations</a>
        </div>
        <div>
          <a href="https://github.com/christopherkarani/Terra" className="px-4 py-2 rounded-lg bg-white/5 border border-white/10 text-xs font-bold hover:bg-white/10 transition-all uppercase tracking-widest mono">Star on GitHub</a>
        </div>
      </nav>

      {/* Hero */}
      <section className="relative pt-24 pb-32 px-6 overflow-hidden">
        <div className="max-w-6xl mx-auto flex flex-col items-center text-center">
          <div className="mb-8 p-1 rounded-2xl bg-white/5 border border-white/10 backdrop-blur-lg">
             <img src="terra-banner.svg" alt="Terra Banner" className="w-full max-w-2xl rounded-xl" />
          </div>
          <h1 className="text-5xl md:text-7xl font-black tracking-tight mb-6 bg-gradient-to-b from-white to-gray-400 bg-clip-text text-transparent">
            Stop flying blind with local AI.
          </h1>
          <p className="text-xl text-gray-500 max-w-2xl mb-10 leading-relaxed">
            Terra is a privacy-first observability layer for on-device GenAI. 
            Built on OpenTelemetry, giving you production-grade tracing for inference, embeddings, and agents.
          </p>
          <div className="flex flex-col sm:flex-row gap-4 mb-16">
            <a href="https://github.com/christopherkarani/Terra/blob/main/Docs/Front_Facing_API.md#0-90-second-quickstart--copy-ready-recipes" className="px-8 py-4 rounded-xl bg-indigo-600 text-white font-bold hover:bg-indigo-500 transition-all glow-indigo shadow-lg shadow-indigo-500/20">
              Get Started
            </a>
            <div className="flex items-center gap-3 px-6 py-4 rounded-xl bg-white/5 border border-white/10 mono text-sm group cursor-pointer hover:bg-white/10 transition-all">
              <span className="text-gray-500">$</span>
              <span className="text-cyan-400 font-medium">swift package</span> add terra
              <div className="w-4 h-4 text-gray-600 group-hover:text-cyan-400 transition-colors">
                <svg fill="currentColor" viewBox="0 0 20 20"><path d="M8 3a1 1 0 011-1h2a1 1 0 110 2H9a1 1 0 01-1-1z"></path><path d="M6 3a2 2 0 00-2 2v11a2 2 0 002 2h8a2 2 0 002-2V5a2 2 0 00-2-2 3 3 0 01-3 3H9a3 3 0 01-3-3z"></path></svg>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Feature Showcase */}
      <section id="documentation" className="max-w-6xl mx-auto px-6 py-24 border-t border-white/5">
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-24">
          <FeatureCard 
            title="Zero-Code Auto-Instrumentation" 
            description="Enable tracing for CoreML and HTTP AI APIs with one line. No logic changes needed."
            icon={<svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 10V3L4 14h7v7l9-11h-7z" /></svg>}
          />
          <FeatureCard 
            title="Privacy by Design" 
            description="Redacted privacy is the default. No raw prompt/response capture unless explicitly enabled per call."
            icon={<svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z" /></svg>}
          />
          <FeatureCard 
            title="Multi-Runtime Ready" 
            description="Native support for MLX, Llama.cpp, CoreML, and Apple's newest Foundation Models."
            icon={<svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 11H5m14 0a2 2 0 012 2v6a2 2 0 01-2 2H5a2 2 0 01-2-2v-6a2 2 0 012-2m14 0V9a2 2 0 00-2-2M5 11V9a2 2 0 012-2m0 0V5a2 2 0 012-2h6a2 2 0 012 2v2M7 7h10" /></svg>}
          />
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-12 items-center">
          <div className="space-y-6">
            <h2 className="text-4xl font-black">Instrumentation in seconds.</h2>
            <p className="text-gray-500 leading-relaxed">
              Start with one-line setup, then compose typed infer/stream/embed/agent/tool/safety calls as your app grows.
            </p>
            <ul className="space-y-4">
              <li className="flex gap-3 text-sm text-gray-400">
                <span className="text-emerald-500 font-black">✓</span> 
                <strong>Step 1:</strong> One call with <code>try await Terra.start(.init(preset: .quickstart))</code>.
              </li>
              <li className="flex gap-3 text-sm text-gray-400">
                <span className="text-emerald-500 font-black">✓</span> 
                <strong>Step 2:</strong> Canonical composable API: <code>infer/stream/embed/agent/tool/safety + run</code>.
              </li>
              <li className="flex gap-3 text-sm text-gray-400">
                <span className="text-emerald-500 font-black">✓</span> 
                <strong>Step 3:</strong> Add macros and advanced seams only when you need them.
              </li>
            </ul>
          </div>
          <div className="space-y-6">
            <CodeBlock 
              title="AppDelegate.swift"
              code={`import Terra

	@main
	class AppDelegate: UIResponder, UIApplicationDelegate {
	    func application(...) {
	        // One line for global auto-instrumentation
	        Task { try? await Terra.start() }
	        
	        return true
	    }
	}`}
            />
             <CodeBlock 
              title="Recipe.swift"
              code={`import Terra

let answer = try await Terra
    .infer(
        Terra.ModelID("gpt-4o-mini"),
        prompt: "Summarize yesterday's changes",
        provider: Terra.ProviderID("openai"),
        runtime: Terra.RuntimeID("http_api")
    )
    .run { trace in
        trace.tokens(input: 42, output: 18)
        return "stubbed-response"
    }`}
            />
          </div>
        </div>
      </section>

      {/* Persistence / OTLP Section */}
      <section className="bg-black/40 py-24 border-y border-white/5">
        <div className="max-w-6xl mx-auto px-6">
          <div className="grid grid-cols-1 lg:grid-cols-2 gap-16 items-center">
             <div className="order-2 lg:order-1">
                <CodeBlock 
	                  title="Persistence.swift"
	                  code={`var config = Terra.Configuration(preset: .production)
	config.persistence = .defaults()
	Task { try? await Terra.start(config) }`}
	                />
             </div>
             <div className="order-1 lg:order-2 space-y-6">
                <h2 className="text-4xl font-black">Export anywhere. Persist everywhere.</h2>
                <p className="text-gray-500 leading-relaxed">
                  Terra bridges the gap between on-device inference and your centralized telemetry stack. 
                  Ship to any OTLP-compatible backend with on-device buffering for intermittent connectivity.
                </p>
                <div className="flex flex-wrap gap-4 pt-4">
                  <div className="px-3 py-1 rounded bg-white/5 border border-white/10 text-[10px] font-bold tracking-widest uppercase text-gray-500">OTLP/HTTP</div>
                  <div className="px-3 py-1 rounded bg-white/5 border border-white/10 text-[10px] font-bold tracking-widest uppercase text-gray-500">Signposts</div>
                  <div className="px-3 py-1 rounded bg-white/5 border border-white/10 text-[10px] font-bold tracking-widest uppercase text-gray-500">SQLite Buffer</div>
                </div>
             </div>
          </div>
        </div>
      </section>

      <footer className="py-24 px-6 text-center border-t border-white/5">
        <div className="w-12 h-12 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center text-white font-black text-lg mx-auto mb-8">T</div>
        <p className="text-gray-600 text-sm mb-4">© 2026 Christopher Karani. Apache-2.0 License.</p>
        <div className="flex justify-center gap-8 text-xs font-bold text-gray-500 uppercase tracking-widest mono">
          <a href="https://github.com/christopherkarani/Terra/blob/main/Docs/Front_Facing_API.md" className="hover:text-white transition-colors">Docs</a>
          <a href="https://github.com/christopherkarani/Terra" className="hover:text-white transition-colors">GitHub</a>
          <a href="https://github.com/christopherkarani/Terra/blob/main/Docs/Front_Facing_API.md#privacy" className="hover:text-white transition-colors">Privacy</a>
        </div>
      </footer>
    </div>
  );
}
