import { spawn } from 'node:child_process';
import fs from 'node:fs';

// Shell-free, bounded process execution. Stop the entire process tree on Windows.
export function runProcess(executable, args, { cwd, env, input = '', timeoutMs = 60000, cancelled = () => false, maximumBytes = 4 * 1024 * 1024, cancellationFile, cancellationGraceMs = 15000 } = {}) {
  return new Promise((resolve, reject) => {
    let child, timer, poll, killTimer, stopped, bytes = 0, stdout = '', stderr = '';
    function kill() {
      if (!child?.pid) return;
      if (process.platform === 'win32') {
        const killer = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
        killer.on('error', () => child.kill('SIGKILL'));
        killer.on('exit', code => { if (code !== 0) child.kill('SIGKILL'); });
      } else {
        try { process.kill(-child.pid, 'SIGKILL'); } catch { child.kill('SIGKILL'); }
      }
    }
    function stop(reason) {
      if (stopped) return; stopped = reason;
      if (cancellationFile) {
        try { fs.writeFileSync(cancellationFile, 'Controller requested cancellation\n', { flag: 'wx' }); }
        catch (error) { if (error.code !== 'EEXIST') { kill(); return; } }
        killTimer = setTimeout(kill, cancellationGraceMs);
      } else kill();
    }
    function cleanup() { clearTimeout(timer); clearInterval(poll); clearTimeout(killTimer); }
    try { child = spawn(executable, args, { cwd, env, shell: false, windowsHide: true, detached: process.platform !== 'win32', stdio: ['pipe', 'pipe', 'pipe'] }); }
    catch { reject(new Error('Process could not start')); return; }
    child.on('error', () => { cleanup(); reject(new Error('Process could not start')); });
    for (const [stream, append] of [[child.stdout, text => { stdout += text; }], [child.stderr, text => { stderr += text; }]]) {
      stream.setEncoding('utf8'); stream.on('data', text => { bytes += Buffer.byteLength(text); if (bytes > maximumBytes) stop('Output limit reached'); else append(text); });
    }
    child.on('close', (code, signal) => {
      cleanup();
      if (stopped) reject(new Error(stopped));
      else if (code !== 0 || signal) reject(Object.assign(new Error('Process failed'), { stdout, stderr, exitCode: code }));
      else resolve({ stdout, stderr });
    });
    child.stdin.on('error', () => {}); child.stdin.end(input);
    timer = setTimeout(() => stop('Process timed out'), timeoutMs);
    poll = setInterval(() => { try { if (cancelled()) stop('Worker paused or approval expired'); } catch { stop('Cancellation check failed'); } }, 250);
  });
}

export function limitedEnvironment(environment = process.env, { agent = false } = {}) {
  const allowed = /^(PATH|SystemRoot|WINDIR|COMSPEC|PATHEXT|TEMP|TMP|HOME|USERPROFILE|APPDATA|LOCALAPPDATA|PROGRAMFILES|PROGRAMFILES\(X86\)|PROGRAMDATA|NUMBER_OF_PROCESSORS)$/i;
  const result = Object.fromEntries(Object.entries(environment).filter(([key]) => allowed.test(key)));
  Object.assign(result, { NO_COLOR: '1', GIT_TERMINAL_PROMPT: '0', GIT_CONFIG_NOSYSTEM: '1' });
  if (agent) Object.assign(result, { CLAUDE_CODE_MAX_OUTPUT_TOKENS: '8192' });
  return result;
}
