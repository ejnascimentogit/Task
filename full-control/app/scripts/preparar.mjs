// Prepara a parte Node do aplicativo: copia a lógica da TV do executor (uma só fonte da verdade) e instala as dependências.
// Rode dentro de full-control/app:  node scripts/preparar.mjs
import { copyFileSync, mkdirSync, rmSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const aqui = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(aqui, '..');
const destino = path.join(app, 'www', 'nodejs');
mkdirSync(destino, { recursive: true });
copyFileSync(path.resolve(app, '..', 'executor', 'src', 'tv-logica.js'), path.join(destino, 'tv-logica.mjs'));
console.log('copiado: tv-logica.mjs');
execSync('npm install --omit=dev --no-audit --no-fund', { cwd: destino, stdio: 'inherit' });
// systeminformation (~40 MB) é trocado por um valor fixo em index.js; sem ele o aplicativo fica bem menor.
for (const lixo of ['systeminformation', '@types', 'undici-types']) rmSync(path.join(destino, 'node_modules', lixo), { recursive: true, force: true });
console.log('dependências da parte Node instaladas');
