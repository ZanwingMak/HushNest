import React from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';
import './style.css';
import { isAndroid, isWindows } from './platform';
class ErrorBoundary extends React.Component<React.PropsWithChildren, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  render() { return this.state.failed ? <main className="fatal"><h1>HushNest</h1><p>应用暂时无法打开 / Could not open the app.</p><button onClick={() => location.reload()}>重新加载 / Reload</button></main> : this.props.children; }
}
createRoot(document.getElementById('root')!).render(<ErrorBoundary><App /></ErrorBoundary>);
if (import.meta.env.PROD && !isAndroid && !isWindows && 'serviceWorker' in navigator) void navigator.serviceWorker.register('./sw.js').catch(() => {});
