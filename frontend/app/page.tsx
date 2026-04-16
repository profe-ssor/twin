import Twin from '@/components/twin';

export default function Home() {
  return (
    <main className="min-h-screen bg-gradient-to-br from-slate-50 to-gray-100">
      <div className="container mx-auto px-4 py-8">
        <div className="max-w-4xl mx-auto">
          <h1 className="text-4xl font-bold text-center text-gray-800 mb-2">
            AI in Production
          </h1>
          <p className="text-center text-gray-600 mb-8">
            Deploy your Digital Twin to the cloud
          </p>

          <div className="h-[600px]">
            <Twin />
          </div>

          <footer className="mt-8 text-center text-sm text-gray-500">
            <a
              href="https://collins-site.onrender.com"
              target="_blank"
              rel="noopener noreferrer"
              className="text-slate-700 underline underline-offset-2 hover:text-slate-900"
            >
              Visit my Website
            </a>
          </footer>
        </div>
      </div>
    </main>
  );
}