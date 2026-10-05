import sys

def ensure_import_os(src):
    """Add `import os` after the __future__ import (which must stay first), or after the module docstring."""
    import re
    if re.search(r"^import os$", src, re.M):
        return src
    m = re.search(r"^from __future__ import [^\n]+\n", src, re.M)
    if m:
        return src[:m.end()] + "import os\n" + src[m.end():]
    m = re.match(r'(\s*(?:"""[\s\S]*?"""|\'\'\'[\s\S]*?\'\'\')\s*\n)', src)
    return (src[:m.end()] + "import os\n" + src[m.end():]) if m else "import os\n" + src

D = sys.argv[1]
p = D + "/server/routes/accounts_auth.py"; s = open(p).read()
assert s.count('samesite="lax"') == 3, s.count('samesite="lax"')   # two cookie sites + one comment
s = ensure_import_os(s)
helper = '''
# Jay 2026-10-02 (local patch, upstream this): SameSite=None lets the Studio be framed by the engine
# workspace on proposals.gopainting.com with the owner's login. Opt-in by env; Lax stays the default.
_SAMESITE = "none" if os.environ.get("OMNIGENT_COOKIE_SAMESITE", "").strip().lower() == "none" else "lax"
'''
assert s.count("\ndef _set_session_cookie(") == 1
s = s.replace("\ndef _set_session_cookie(", helper + "\n\ndef _set_session_cookie(", 1)
old1 = '        secure=secure,\n        samesite="lax",\n        path="/",\n    )\n'
assert s.count(old1) == 1
s = s.replace(old1, '        secure=secure or _SAMESITE == "none",\n        samesite=_SAMESITE,\n        path="/",\n    )\n', 1)
old2 = '        secure=secure,\n        httponly=True,\n        samesite="lax",\n'
assert s.count(old2) == 1
s = s.replace(old2, '        secure=secure or _SAMESITE == "none",\n        httponly=True,\n        samesite=_SAMESITE,\n', 1)
assert s.count('samesite="lax"') == 1   # only the comment remains
open(p, "w").write(s)
a = D + "/server/app.py"; t = open(a).read()
anchor = "        app.add_middleware(BasePathMiddleware, base_path=resolved_base_path)\n\n    return app\n"
assert t.count(anchor) == 1
t = t.replace(anchor, '''        app.add_middleware(BasePathMiddleware, base_path=resolved_base_path)

    # Jay 2026-10-02 (local patch, upstream this): a browser page on another origin (the engine workspace on
    # proposals.gopainting.com) may call the API with the owner's cookie when its origin is allow-listed.
    _cors = [o.strip() for o in os.environ.get("OMNIGENT_CORS_ORIGINS", "").split(",") if o.strip()]
    if _cors:
        from fastapi.middleware.cors import CORSMiddleware
        app.add_middleware(CORSMiddleware, allow_origins=_cors, allow_credentials=True, allow_methods=["*"], allow_headers=["*"])

    return app
''')
t = ensure_import_os(t)
open(a, "w").write(t)
print("patched both")
