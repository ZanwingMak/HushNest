const { contextBridge, ipcRenderer } = require('electron');
const subscribe = (channel, callback) => { const handler = () => callback(); ipcRenderer.on(channel, handler); return () => ipcRenderer.removeListener(channel, handler); };
contextBridge.exposeInMainWorld('hushnestDesktop', {
  route: () => ipcRenderer.invoke('hushnest:route'),
  keepAwake: active => ipcRenderer.invoke('hushnest:awake', active === true),
  onSuspend: callback => subscribe('hushnest:suspend', callback),
});
contextBridge.exposeInMainWorld('hushnestAudio', {
  play: data => ipcRenderer.invoke('hushnest:play', data),
  stop: () => ipcRenderer.invoke('hushnest:stop'),
  volume: value => ipcRenderer.invoke('hushnest:volume', value),
  cacheMedia: data => ipcRenderer.invoke('hushnest:cache', data),
  deleteMedia: id => ipcRenderer.invoke('hushnest:delete', id),
  onRouteLost: callback => subscribe('hushnest:routeLost', callback),
});
