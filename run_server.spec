# run_server.spec 파일에 이 내용을 붙여넣으세요.

# -*- mode: python ; coding: utf-8 -*-

a = Analysis(
    ['py/run_server.py'],
    pathex=[],
    binaries=[],
    datas=[('py/.env', '.')],
    hiddenimports=[
        'waitress',
        'pysqlite3_binary',
        'langchain_google_genai',
        'langchain_community',
        'langgraph',
        'chromadb',
        'google.generativeai',
        'numpy'
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='memordo_ai_backend',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='memordo_ai_backend',
)