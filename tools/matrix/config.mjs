import fs from 'node:fs';
import path from 'node:path';
import { validateUsageConfig } from './usage.mjs';
import { BATCH_LIMIT } from './policy.mjs';

const TOP = ['repositorySlug', 'baseBranch', 'sourceDirectory', 'stateDirectory', 'worktreeRoot', 'promptDirectory', 'idPrefixes',
  'dailyTime', 'batchLimit', 'claudeUsage', 'worker', 'boardPickup'];
const WORKER = ['maximumPrompts', 'maximumTurns', 'maximumBudgetUsd', 'timeoutSeconds', 'maximumRunMinutes', 'maximumRepairs', 'maximumTokens'];
const isAbsolute = value => typeof value === 'string' && (path.posix.isAbsolute(value) || path.win32.isAbsolute(value));
const positiveInteger = value => Number.isInteger(value) && value > 0;

// Strict: unknown keys, wrong types, relative paths and a batch other than one are errors.
export function validateConfig(config) {
  const fail = message => { throw new Error(`Invalid Matrix configuration: ${message}`); };
  if (!config || typeof config !== 'object' || Array.isArray(config)) fail('expected an object');
  for (const key of Object.keys(config)) if (!TOP.includes(key)) fail(`unknown key ${key}`);
  if (typeof config.repositorySlug !== 'string' || !/^[\w.-]+\/[\w.-]+$/.test(config.repositorySlug)) fail('repositorySlug must be owner/name');
  if (typeof config.baseBranch !== 'string' || !/^[\w./-]+$/.test(config.baseBranch)) fail('baseBranch must be a branch name');
  for (const key of ['sourceDirectory', 'stateDirectory', 'worktreeRoot']) if (!(key === 'sourceDirectory' && config[key] === undefined) && !isAbsolute(config[key])) fail(`${key} must be an absolute path`);
  if (typeof config.promptDirectory !== 'string' || !/^[\w-]+$/.test(config.promptDirectory)) fail('promptDirectory must be a single folder name');
  if (!Array.isArray(config.idPrefixes) || config.idPrefixes.length === 0 || config.idPrefixes.some(p => typeof p !== 'string' || !/^[A-Z][A-Z0-9]*$/.test(p))) fail('idPrefixes must be upper-case prefixes');
  if (config.dailyTime !== undefined && (typeof config.dailyTime !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(config.dailyTime))) fail('dailyTime must be HH:MM');
  if (config.batchLimit !== undefined && config.batchLimit !== BATCH_LIMIT) fail('batchLimit must be 1');
  try { validateUsageConfig(config.claudeUsage); } catch (error) { fail(error.message); }
  const worker = config.worker ?? {};
  if (typeof worker !== 'object' || Array.isArray(worker)) fail('worker must be an object');
  for (const key of Object.keys(worker)) if (!WORKER.includes(key)) fail(`unknown worker key ${key}`);
  if (worker.maximumPrompts !== undefined && worker.maximumPrompts !== 1) fail('worker.maximumPrompts must be 1');
  for (const key of ['maximumTurns', 'timeoutSeconds', 'maximumRunMinutes', 'maximumRepairs']) {
    if (worker[key] !== undefined && !positiveInteger(worker[key])) fail(`worker.${key} must be a positive integer`);
  }
  if (worker.maximumBudgetUsd !== undefined && !(typeof worker.maximumBudgetUsd === 'number' && worker.maximumBudgetUsd > 0)) fail('worker.maximumBudgetUsd must be a positive number');
  if (worker.maximumTokens !== undefined && !(Number.isInteger(worker.maximumTokens) && worker.maximumTokens >= 10000 && worker.maximumTokens <= 100000000)) fail('worker.maximumTokens must be an integer from 10,000 to 100,000,000');
  if (config.boardPickup !== undefined) validateBoardPickup(config.boardPickup, fail);
  return config;
}

const BOARD = ['enabled', 'dryRun', 'projectId', 'statusFieldId', 'options', 'repository', 'ownerLogin', 'tokenFile'];
const OPTIONS = ['backlog', 'todo', 'doing', 'blocked', 'done'];
const text = value => typeof value === 'string' && value.length > 0;

// boardPickup may be empty while the board is not set up. Once enabled, every ID must be present.
function validateBoardPickup(board, fail) {
  if (typeof board !== 'object' || board === null || Array.isArray(board)) fail('boardPickup must be an object');
  for (const key of Object.keys(board)) if (!BOARD.includes(key)) fail(`unknown boardPickup key ${key}`);
  for (const key of ['enabled', 'dryRun']) if (board[key] !== undefined && typeof board[key] !== 'boolean') fail(`boardPickup.${key} must be true or false`);
  for (const key of ['projectId', 'statusFieldId', 'ownerLogin']) if (board[key] !== undefined && !text(board[key])) fail(`boardPickup.${key} must be text`);
  if (board.repository !== undefined && !/^[\w.-]+\/[\w.-]+$/.test(board.repository)) fail('boardPickup.repository must be owner/name');
  if (board.tokenFile !== undefined && !isAbsolute(board.tokenFile)) fail('boardPickup.tokenFile must be an absolute path');
  if (board.options !== undefined) {
    if (typeof board.options !== 'object' || board.options === null || Array.isArray(board.options)) fail('boardPickup.options must be an object');
    for (const key of Object.keys(board.options)) if (!OPTIONS.includes(key)) fail(`unknown boardPickup option ${key}`);
    for (const key of OPTIONS) if (board.options[key] !== undefined && !text(board.options[key])) fail(`boardPickup.options.${key} must be text`);
  }
  if (board.enabled === true) {
    for (const key of ['projectId', 'statusFieldId', 'ownerLogin', 'tokenFile']) if (!text(board[key])) fail(`boardPickup.${key} is required when pickup is enabled`);
    for (const key of OPTIONS) if (!text(board.options?.[key])) fail(`boardPickup.options.${key} is required when pickup is enabled`);
  }
}

export function readConfig(file) {
  let parsed;
  try { parsed = JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch { throw new Error('Matrix configuration could not be read as JSON'); }
  return validateConfig(parsed);
}
