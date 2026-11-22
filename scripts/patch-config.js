#!/usr/bin/env node
'use strict';

const fs = require('fs');

const args = process.argv.slice(2);
const configPath = args.shift();

if (!configPath || args.length === 0) {
  console.error('Usage: patch-config.js <config.json> [--harden] [--auto-backup] [--production|--staging]');
  process.exit(2);
}

let config;
try {
  config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (err) {
  console.error(`Cannot read ${configPath}: ${err.message}`);
  process.exit(1);
}

if (!config.domains || !config.domains['']) {
  console.error('config.json has no default domain ("domains": { "": ... }).');
  process.exit(1);
}

const domain = config.domains[''];
const changed = [];

for (const arg of args) {
  switch (arg) {
    case '--harden':
      domain.newAccounts = false;
      domain.twoFactorCookieDurationDays = 7;
      domain.passwordRequirements = {
        ...(domain.passwordRequirements || {}),
        min: 12,
        force2factor: true,
      };
      // The blog post calls this key "twofactor"; current MeshCentral uses
      // "force2factor". Remove the stale key if a previous config had it.
      delete domain.passwordRequirements.twofactor;
      delete domain.passwordRequirements.twoFactor;
      changed.push('newAccounts=false, force2factor=true, min password length 12');
      break;

    case '--auto-backup':
      config.settings = config.settings || {};
      config.settings.autoBackup = {
        ...(config.settings.autoBackup || {}),
        backupIntervalHours: 24,
        keepLastDaysBackup: 30,
        backupPath: '/opt/meshcentral/meshcentral-backups',
      };
      changed.push('autoBackup every 24h, keep 30 days');
      break;

    case '--production':
      config.letsencrypt = config.letsencrypt || {};
      config.letsencrypt.production = true;
      changed.push('letsencrypt.production=true');
      break;

    case '--staging':
      config.letsencrypt = config.letsencrypt || {};
      config.letsencrypt.production = false;
      changed.push('letsencrypt.production=false');
      break;

    default:
      console.error(`Unknown option: ${arg}`);
      process.exit(2);
  }
}

const tmp = `${configPath}.tmp-${process.pid}`;
fs.writeFileSync(tmp, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
fs.renameSync(tmp, configPath);
fs.chmodSync(configPath, 0o600);
console.log(`Updated ${configPath}: ${changed.join('; ')}`);
