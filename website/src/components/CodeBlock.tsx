import React from 'react';

interface CodeBlockProps {
  code: string;
  language?: string;
  title?: string;
}

export const CodeBlock: React.FC<CodeBlockProps> = ({ code, title }) => {
  return (
    <div className="rounded-xl overflow-hidden border border-white/10 bg-[#1A1C29] shadow-2xl">
      {title && (
        <div className="px-4 py-2 border-b border-white/5 flex items-center justify-between bg-black/20">
          <div className="flex gap-1.5">
            <div className="w-2.5 h-2.5 rounded-full bg-red-500/80" />
            <div className="w-2.5 h-2.5 rounded-full bg-amber-500/80" />
            <div className="w-2.5 h-2.5 rounded-full bg-emerald-500/80" />
          </div>
          <span className="text-[11px] font-medium text-gray-500 uppercase tracking-widest mono">{title}</span>
        </div>
      )}
      <div className="p-4 overflow-x-auto">
        <pre className="text-sm mono leading-relaxed">
          {code.split(/\r?\n/).map((line, i) => {
            // Very basic highlighter simulation
            const isComment = line.trim().startsWith('//');
            const isKeyword = line.includes('import') || line.includes('try') || line.includes('func') || line.includes('struct') || line.includes('await') || line.includes('static');
            const isString = line.includes('"');
            
            let colorClass = 'text-gray-300';
            if (isComment) colorClass = 'text-gray-500 italic';
            else if (isKeyword) colorClass = 'text-indigo-400';
            else if (isString) colorClass = 'text-cyan-400';

            return (
              <div key={i} className="flex gap-4">
                <span className="text-gray-700 select-none w-4 text-right">{i + 1}</span>
                <code className={colorClass}>{line}</code>
              </div>
            );
          })}
        </pre>
      </div>
    </div>
  );
};
