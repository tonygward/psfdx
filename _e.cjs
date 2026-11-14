const fs = require('fs');
let s = fs.readFileSync('scripts/release/Build-GalleryPackage.ps1', 'utf8');
const a = '"\'$($folderFor[$_])\$($folderFor[$_]).psd1\'"';
if (!s.includes(a)) throw new Error('anchor');
s = s.replace(a, '"\'$($folderFor[$_])/$($folderFor[$_]).psd1\'"');
fs.writeFileSync('scripts/release/Build-GalleryPackage.ps1', s);
