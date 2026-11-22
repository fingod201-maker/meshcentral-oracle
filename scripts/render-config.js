#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const [templatePath, outputPath, domain, email, title, production] = process.argv.slice(2);

if (!templatePath || !outputPath || !domain || !email || !title || production === undefined) {
  console.error('Usage: render-config.js <template> <output> <domain> <email> <title> <true|false>');
  process.exit(2);
}

if (production !== 'true' && production !== 'false') {
  console.error('The production argument must be "true" or "false".');
  process.exit(2);
}

const replacements = {
  '"__DOMAIN__"': JSON.stringify(domain),
  '"__LE_EMAIL__"': JSON.stringify(email),
  '"__SITE_TITLE__"': JSON.stringify(title),
  '__LE_PRODUCTION__': production,
};

let text = fs.readFileSync(templatePath, 'utf8');
for (const [placeholder, value] of Object.entries(replacements)) {
  text = text.split(placeholder).join(value);
}

if (/__DOMAIN__|__LE_EMAIL__|__SITE_TITLE__|__LE_PRODUCTION__/.test(text)) {
  console.error('Unreplaced placeholder remains in the config template.');
  process.exit(1);
}

let config;
try {
  config = JSON.parse(text);
} catch (err) {
  console.error(`Rendered config is not valid JSON: ${err.message}`);
  process.exit(1);
}

// A redeploy must not silently undo hardening. If a config already exists,
// keep the security-relevant settings from it. Let's Encrypt is only ever
// upgraded from staging to production here; use patch-config.js --staging to
// deliberately go back.
const preserved = [];
let existing = null;
try {
  if (fs.existsSync(outputPath)) {
    existing = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
  }
} catch (err) {
  console.error(`Cannot read existing ${outputPath}: ${err.message}`);
  process.exit(1);
}

if (existing && existing.domains && existing.domains['']) {
  const oldDomain = existing.domains[''];
  const newDomain = config.domains[''];

  if (oldDomain.newAccounts === false) {
    newDomain.newAccounts = false;
    preserved.push('newAccounts=false');
  }
  if (oldDomain.passwordRequirements && typeof oldDomain.passwordRequirements === 'object') {
    newDomain.passwordRequirements = {
      ...(newDomain.passwordRequirements || {}),
      ...oldDomain.passwordRequirements,
    };
    preserved.push('passwordRequirements');
  }
  if (typeof oldDomain.twoFactorCookieDurationDays === 'number') {
    newDomain.twoFactorCookieDurationDays = oldDomain.twoFactorCookieDurationDays;
    preserved.push('twoFactorCookieDurationDays');
  }
}

if (existing && existing.settings && existing.settings.autoBackup !== undefined) {
  config.settings.autoBackup = existing.settings.autoBackup;
  preserved.push('autoBackup');
}

if (existing && existing.letsencrypt && existing.letsencrypt.production === true) {
  config.letsencrypt.production = true;
  preserved.push("letsencrypt.production=true");
}

fs.mkdirSync(path.dirname(outputPath), { recursive: true });
const tmp = `${outputPath}.tmp-${process.pid}`;
fs.writeFileSync(tmp, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
fs.chmodSync(tmp, 0o600);
fs.renameSync(tmp, outputPath);
console.log(`Wrote ${outputPath}${preserved.length ? ` (preserved ${preserved.join(', ')})` : ''}`);
