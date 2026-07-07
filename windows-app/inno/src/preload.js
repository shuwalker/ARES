const { contextBridge } = require('electron');
contextBridge.exposeInMainWorld('__ARES_NATIVE__', { platform: process.platform });
