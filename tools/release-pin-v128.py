#!/usr/bin/env python3
"""Build v1.2.8 using the exact user-validated bridge DLL and v1.2.6 runtime.

No rendering DLL, feeder, DXVK or FusionFix components are recompiled. The
only changed runtime content is the pinned b-bridge client and its config.
"""
import argparse
import hashlib
import io
import re
import shutil
import zipfile
from pathlib import Path

VERSION = "1.2.8"
BASE_RUNTIME_SHA = "44960556C6643D48158B57F8B23659E152879FFD2B5591C3C8E323ACA91DD6FB"
TESTED_CLIENT_SHA = "B2FE0313971080A7D5D011BC047F66A8E540FC55B9C279A81A3A9CB9D4EEFDDF"
FEEDER_SHA = "C8C7D555F6E1BFBA939560DB3F641BA64FC480D07E9A2C193E0CD468FC026550"
RESH_PATCH_SHA = "D5BD8CB2B6E935506888EA71711361B9AFCD72ED7C70926C0F52E8F8E47C7510"

def sha(data):
    return hashlib.sha256(data).hexdigest().upper()

def need(test, message):
    if not test:
        raise RuntimeError(message)

def replace_once(source, old, new, description):
    need(source.count(old) == 1, f"Unexpected {description} anchor count {source.count(old)}")
    return source.replace(old, new, 1)

def change_config(source):
    t = source.decode("utf-8-sig")
    nl = "\r\n" if "\r\n" in t else "\n"
    def set_existing(k, val):
        nonlocal t
        regex = re.compile(r"(?m)^[ \t]*" + re.escape(k) + r"[ \t]*=[ \t]*[^\r\n]*")
        need(len(regex.findall(t)) == 1, f"Missing or duplicate bridge key: {k}")
        t = regex.sub(k + " = " + val, t)
    set_existing("eliminateRedundantSetterCalls", "True")
    set_existing("clientStateBatch", "True")
    mask = "clientRedundantBypassMask"
    need(not re.search(r"(?m)^[ \t]*" + re.escape(mask) + r"[ \t]*=", t),
         "Base bridge already contains the diagnostic mask key")
    t = t.rstrip("\r\n") + nl + (
        "# v1.2.8 validated b-bridge shader/stream binding fix: bitmask 0xFC000" + nl +
        mask + " = 1032192" + nl)
    return t.encode("utf-8")

def fast_upgrade():
    return r'''
# Fast, reversible upgrade from 1.2.6. Do NOT touch FusionFix, ReShade,
# DXVK, the user's mods, or any DLSS/FSR settings.
function Repair-V126BridgePin([string]$Root){
    $receiptFile=Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    $clientFile=Join-Path $Root 'd3d9.dll'
    $configFile=Join-Path $Root '.trex\bridge.conf'
    if(-not(Test-Foundation $Root) -or
       -not(Test-Path -LiteralPath $receiptFile -PathType Leaf) -or
       -not(Test-Path -LiteralPath $clientFile -PathType Leaf) -or
       -not(Test-Path -LiteralPath $configFile -PathType Leaf)){return $false}
    $oldReceipt=[IO.File]::ReadAllText($receiptFile)
    if($oldReceipt -notmatch '(?m)^Version=1\.2\.6\r?$'){return $false}
    $out=Join-Path (Get-AutoTemp) 'v127-bridge-pin'
    Expand-Archive -LiteralPath $RuntimePackage -DestinationPath $out -Force
    $source=Join-Path $out 'd3d9.dll'
    Assert-SHA256 $source 'B2FE0313971080A7D5D011BC047F66A8E540FC55B9C279A81A3A9CB9D4EEFDDF' 'v1.2.8 pinned client'
    $backup=Join-Path $Root ('_GTAIV_SCALING_PRE127_BACKUP_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    New-Item -ItemType Directory -Path $backup -Force|Out-Null
    Copy-Item -LiteralPath $clientFile -Destination (Join-Path $backup 'd3d9.dll') -Force
    Copy-Item -LiteralPath $configFile -Destination (Join-Path $backup 'bridge.conf') -Force
    Copy-Item -LiteralPath $receiptFile -Destination (Join-Path $backup 'GTAIV_SCALING_INSTALLED.txt') -Force
    try{
        Copy-Item -LiteralPath $source -Destination $clientFile -Force
        Set-KeyEquals $configFile 'eliminateRedundantSetterCalls' 'True'
        Set-KeyEquals $configFile 'clientStateBatch' 'True'
        Set-KeyEquals $configFile 'clientRedundantBypassMask' '1032192'
        Assert-SHA256 $clientFile 'B2FE0313971080A7D5D011BC047F66A8E540FC55B9C279A81A3A9CB9D4EEFDDF' 'installed pinned client'
        $updated=[regex]::Replace($oldReceipt,'(?m)^Version=1\.2\.6(?=\r?$)','Version=1.2.8')
        if($updated-eq$oldReceipt){Fail 'Version receipt was not updated'}
        $updated=$updated.TrimEnd([char]13,[char]10)+[Environment]::NewLine+
            'BridgeShaderStreamPin=1032192'+[Environment]::NewLine+
            "Pre127Backup=$backup"+[Environment]::NewLine
        [IO.File]::WriteAllText($receiptFile,$updated,[Text.UTF8Encoding]::new($false))
        Write-Host ('Pinned b-bridge client installed; backup: '+$backup) -ForegroundColor Green
        return $true
    }catch{
        foreach($name in @('d3d9.dll','bridge.conf','GTAIV_SCALING_INSTALLED.txt')){
            $to=if($name-eq'bridge.conf'){$configFile}else{Join-Path $Root $name}
            Copy-Item -LiteralPath (Join-Path $backup $name) -Destination $to -Force -ErrorAction SilentlyContinue
        }
        throw
    }
}

'''

def maintenance_fast_path():
    return r'''
# Preserve the proven v1.2.7 renderer on installer-only repairs.
function Test-ApprovedV127Bridge([string]$Root){
    $receipt=Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    $dll=Join-Path $Root 'd3d9.dll'
    $config=Join-Path $Root '.trex\bridge.conf'
    if(-not(Test-Foundation $Root) -or -not(Test-Path -LiteralPath $receipt -PathType Leaf) -or
       -not(Test-Path -LiteralPath $dll -PathType Leaf) -or
       -not(Test-Path -LiteralPath $config -PathType Leaf)){return $false}
    if((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToUpperInvariant() -ne
       'B2FE0313971080A7D5D011BC047F66A8E540FC55B9C279A81A3A9CB9D4EEFDDF'){return $false}
    return ([IO.File]::ReadAllText($config) -match '(?m)^\s*clientRedundantBypassMask\s*=\s*1032192\s*
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", type=Path, required=True, help="Unpacked v1.2.6 release-prep artifact")
    ap.add_argument("--client", type=Path, required=True, help="Successful selective-mask diagnostic d3d9.dll")
    args = ap.parse_args()
    repo=Path.cwd()
    runtime_zip=args.base / "installer/payload/GTAIV-Scaling-Runtime-v1.2.6.zip"
    need(runtime_zip.is_file(), f"Missing {runtime_zip}")
    need(sha(runtime_zip.read_bytes())==BASE_RUNTIME_SHA, "Wrong v1.2.6 runtime")
    need(sha(args.client.read_bytes())==TESTED_CLIENT_SHA, "Wrong or untested bridge DLL")
    src=repo / "_runtime127"
    if src.exists(): shutil.rmtree(src)
    src.mkdir()
    with zipfile.ZipFile(runtime_zip) as archive:
        names=set(archive.namelist())
        need("d3d9.dll" in names and "bridge.conf" in names and "SHA256SUMS.txt" in names, "Bad old runtime")
        for item in archive.infolist():
            target=src / item.filename
            if item.is_dir(): target.mkdir(parents=True,exist_ok=True)
            else:
                target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(archive.read(item.filename))
    original={f.relative_to(src).as_posix():sha(f.read_bytes()) for f in src.rglob("*") if f.is_file()}
    need(sha((src/"dlss5-feed.addon64").read_bytes())==FEEDER_SHA,"Feeder mismatch")
    (src/"d3d9.dll").write_bytes(args.client.read_bytes())
    (src/"bridge.conf").write_bytes(change_config((src/"bridge.conf").read_bytes()))
    (src/"GTAIV-SCALING-VERSION.txt").write_bytes(b"GTA IV Scaling runtime 1.2.8 - pinned shader/stream state fix\n")
    hashes=[]
    for f in sorted(src.rglob("*")):
        if f.is_file() and f.name != "SHA256SUMS.txt":
            hashes.append(f"{sha(f.read_bytes())}  {f.relative_to(src).as_posix()}")
    (src/"SHA256SUMS.txt").write_text("\n".join(hashes)+"\n",encoding="ascii")
    changed=[rel for rel,old in original.items() if sha((src/rel).read_bytes())!=old]
    expected={"d3d9.dll","bridge.conf","GTAIV-SCALING-VERSION.txt","SHA256SUMS.txt"}
    need(set(changed)==expected, f"Unexpected changed runtime files: {changed}")
    config=(src/"bridge.conf").read_text(encoding="utf-8")
    for setting in ["eliminateRedundantSetterCalls = True","clientStateBatch = True","clientRedundantBypassMask = 1032192"]:
        need(setting in config, f"Missing pinned setting: {setting}")

    payload=repo/"installer/payload"
    payload.mkdir(parents=True,exist_ok=True)
    out_zip=payload/"GTAIV-Scaling-Runtime-v1.2.8.zip"
    with zipfile.ZipFile(out_zip,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in sorted(src.rglob("*")):
            if file.is_file():z.write(file,file.relative_to(src).as_posix())
    runtimehash=sha(out_zip.read_bytes())
    (payload/"GTAIV-Scaling-Runtime-v1.2.8.sha256").write_text(runtimehash+"\n",encoding="ascii")
    (payload/"dlss5-feed-v1.2.8.sha256").write_text(FEEDER_SHA+"\n",encoding="ascii")
    patch_src=args.base/"installer/payload/ReShade64-bbridge.dll"
    need(sha(patch_src.read_bytes())==RESH_PATCH_SHA,"Wrong ReShade input patch")
    shutil.copyfile(patch_src,payload/"ReShade64-bbridge.dll")

    core=(repo/"install/core/Install-DLAA-Core.bat").read_text(encoding="utf-8")
    core=replace_once(core,"A0796FA04DFACEC7997B08BEFE1933EFBB17D2BC62478CB41B8C89750674CEE3",runtimehash,"foundation runtime checksum")
    core=replace_once(core,"B6D7D9B050C4F32642A528E7700F38A0510795C7D61D30665DC96AF270B9ED27",FEEDER_SHA,"foundation feeder checksum")
    core=core.replace("GTAIV-DLSS-Setup.exe","GTAIV-Scaling-Setup-v1.2.8.exe")
    match=re.search(r"(?s)\$RuntimeHashes=@\{(.*?)\}",core)
    need(match is not None,"RuntimeHashes table missing")
    line=re.compile(r"(?m)^([ \t]*'([^']+)'[ \t]*=[ \t]*')([0-9A-Fa-f]{64})('[ \t]*;?[ \t]*\r?$)")
    n=[0]
    def replace_entry(m):
        rel=m.group(2)
        f=src/rel
        need(f.is_file(),f"Missing foundation runtime file {rel}")
        n[0]+=1
        return m.group(1)+sha(f.read_bytes())+m.group(4)
    block=line.sub(replace_entry,match.group(1))
    need(n[0]>=10,f"Only {n[0]} foundation hashes")
    core=core[:match.start(1)]+block+core[match.end(1):]
    (payload/"Install-DLAA-Core-v1.2.8.bat").write_text(core,encoding="utf-8")

    runner=(repo/"installer/Run-Scaling-Action-v128.ps1").read_text(encoding="utf-8")
    runner=replace_once(runner,"$Version='1.2.6'","$Version='1.2.8'","runner version")
    runner=runner.replace("v1.2.6","v1.2.8")
    runner=replace_once(runner,
        "if(Repair-V122AspectRatio $Root){Upgrade-AddonUi $Root;TryAutoNrUpdate $Root $NrPackage;return}",
        "# The old v1.2.2-1.2.4 config-only shortcut must NOT skip the v1.2.8 bridge DLL.",
        "old config-only shortcut")
    runner=replace_once(runner,"function Install-Scaling([string]$Root){",
        fast_upgrade()+maintenance_fast_path()+"function Install-Scaling([string]$Root){","hotfix insertion point")
    runner=replace_once(runner,
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}",
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}\n    if(Repair-V126BridgePin $Root){Write-Result 'GTA IV Scaling 1.2.8 pinned bridge upgrade completed without modifying mods, scaling profiles or FusionFix.';return}",
        "v1.2.6 fast hotfix invocation")
    for key,value in [("__SCALING_RUNTIME_SHA256__",runtimehash),("__SCALING_FEEDER_SHA256__",FEEDER_SHA)]:
        runner=replace_once(runner,key,value,f"runner {key}")
    (payload/"Run-Scaling-Action.ps1").write_text(runner,encoding="utf-8")

    iss_path=repo/"installer/GTAIV-Scaling-Setup-v128.iss"
    iss=iss_path.read_text(encoding="utf-8")
    need(iss.count("1.2.6")>=8,"Unexpected Inno source version")
    iss=iss.replace("1.2.6","1.2.8")
    iss_path.write_text(iss,encoding="utf-8")
    need("1.2.6" not in iss,"Stale Inno version")
    print(f"PINNED CLIENT SHA256={TESTED_CLIENT_SHA}")
    print(f"RUNTIME ZIP SHA256={runtimehash}")
    print(f"FEEDER SHA256={FEEDER_SHA}")
    print(f"CHANGED RUNTIME FILES={sorted(changed)}")
    print(f"FOUNDATION HASH ENTRIES={n[0]}")
    print("PASS: payload and Inno sources ready")
    
if __name__=="__main__":
    main()
)
}
function Repair-V127InstallerOnly([string]$Root){
    $receipt=Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    if(-not(Test-Path -LiteralPath $receipt -PathType Leaf)){return $false}
    $old=[IO.File]::ReadAllText($receipt)
    if($old -notmatch '(?m)^Version=1\.2\.7\r?
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", type=Path, required=True, help="Unpacked v1.2.6 release-prep artifact")
    ap.add_argument("--client", type=Path, required=True, help="Successful selective-mask diagnostic d3d9.dll")
    args = ap.parse_args()
    repo=Path.cwd()
    runtime_zip=args.base / "installer/payload/GTAIV-Scaling-Runtime-v1.2.6.zip"
    need(runtime_zip.is_file(), f"Missing {runtime_zip}")
    need(sha(runtime_zip.read_bytes())==BASE_RUNTIME_SHA, "Wrong v1.2.6 runtime")
    need(sha(args.client.read_bytes())==TESTED_CLIENT_SHA, "Wrong or untested bridge DLL")
    src=repo / "_runtime127"
    if src.exists(): shutil.rmtree(src)
    src.mkdir()
    with zipfile.ZipFile(runtime_zip) as archive:
        names=set(archive.namelist())
        need("d3d9.dll" in names and "bridge.conf" in names and "SHA256SUMS.txt" in names, "Bad old runtime")
        for item in archive.infolist():
            target=src / item.filename
            if item.is_dir(): target.mkdir(parents=True,exist_ok=True)
            else:
                target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(archive.read(item.filename))
    original={f.relative_to(src).as_posix():sha(f.read_bytes()) for f in src.rglob("*") if f.is_file()}
    need(sha((src/"dlss5-feed.addon64").read_bytes())==FEEDER_SHA,"Feeder mismatch")
    (src/"d3d9.dll").write_bytes(args.client.read_bytes())
    (src/"bridge.conf").write_bytes(change_config((src/"bridge.conf").read_bytes()))
    (src/"GTAIV-SCALING-VERSION.txt").write_bytes(b"GTA IV Scaling runtime 1.2.8 - pinned shader/stream state fix\n")
    hashes=[]
    for f in sorted(src.rglob("*")):
        if f.is_file() and f.name != "SHA256SUMS.txt":
            hashes.append(f"{sha(f.read_bytes())}  {f.relative_to(src).as_posix()}")
    (src/"SHA256SUMS.txt").write_text("\n".join(hashes)+"\n",encoding="ascii")
    changed=[rel for rel,old in original.items() if sha((src/rel).read_bytes())!=old]
    expected={"d3d9.dll","bridge.conf","GTAIV-SCALING-VERSION.txt","SHA256SUMS.txt"}
    need(set(changed)==expected, f"Unexpected changed runtime files: {changed}")
    config=(src/"bridge.conf").read_text(encoding="utf-8")
    for setting in ["eliminateRedundantSetterCalls = True","clientStateBatch = True","clientRedundantBypassMask = 1032192"]:
        need(setting in config, f"Missing pinned setting: {setting}")

    payload=repo/"installer/payload"
    payload.mkdir(parents=True,exist_ok=True)
    out_zip=payload/"GTAIV-Scaling-Runtime-v1.2.8.zip"
    with zipfile.ZipFile(out_zip,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in sorted(src.rglob("*")):
            if file.is_file():z.write(file,file.relative_to(src).as_posix())
    runtimehash=sha(out_zip.read_bytes())
    (payload/"GTAIV-Scaling-Runtime-v1.2.8.sha256").write_text(runtimehash+"\n",encoding="ascii")
    (payload/"dlss5-feed-v1.2.8.sha256").write_text(FEEDER_SHA+"\n",encoding="ascii")
    patch_src=args.base/"installer/payload/ReShade64-bbridge.dll"
    need(sha(patch_src.read_bytes())==RESH_PATCH_SHA,"Wrong ReShade input patch")
    shutil.copyfile(patch_src,payload/"ReShade64-bbridge.dll")

    core=(repo/"install/core/Install-DLAA-Core.bat").read_text(encoding="utf-8")
    core=replace_once(core,"A0796FA04DFACEC7997B08BEFE1933EFBB17D2BC62478CB41B8C89750674CEE3",runtimehash,"foundation runtime checksum")
    core=replace_once(core,"B6D7D9B050C4F32642A528E7700F38A0510795C7D61D30665DC96AF270B9ED27",FEEDER_SHA,"foundation feeder checksum")
    core=core.replace("GTAIV-DLSS-Setup.exe","GTAIV-Scaling-Setup-v1.2.8.exe")
    match=re.search(r"(?s)\$RuntimeHashes=@\{(.*?)\}",core)
    need(match is not None,"RuntimeHashes table missing")
    line=re.compile(r"(?m)^([ \t]*'([^']+)'[ \t]*=[ \t]*')([0-9A-Fa-f]{64})('[ \t]*;?[ \t]*\r?$)")
    n=[0]
    def replace_entry(m):
        rel=m.group(2)
        f=src/rel
        need(f.is_file(),f"Missing foundation runtime file {rel}")
        n[0]+=1
        return m.group(1)+sha(f.read_bytes())+m.group(4)
    block=line.sub(replace_entry,match.group(1))
    need(n[0]>=10,f"Only {n[0]} foundation hashes")
    core=core[:match.start(1)]+block+core[match.end(1):]
    (payload/"Install-DLAA-Core-v1.2.8.bat").write_text(core,encoding="utf-8")

    runner=(repo/"installer/Run-Scaling-Action-v128.ps1").read_text(encoding="utf-8")
    runner=replace_once(runner,"$Version='1.2.6'","$Version='1.2.8'","runner version")
    runner=runner.replace("v1.2.6","v1.2.8")
    runner=replace_once(runner,
        "if(Repair-V122AspectRatio $Root){Upgrade-AddonUi $Root;TryAutoNrUpdate $Root $NrPackage;return}",
        "# The old v1.2.2-1.2.4 config-only shortcut must NOT skip the v1.2.8 bridge DLL.",
        "old config-only shortcut")
    runner=replace_once(runner,"function Install-Scaling([string]$Root){",
        fast_upgrade()+"function Install-Scaling([string]$Root){","hotfix insertion point")
    runner=replace_once(runner,
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}",
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}\n    if(Repair-V126BridgePin $Root){Write-Result 'GTA IV Scaling 1.2.8 pinned bridge upgrade completed without modifying mods, scaling profiles or FusionFix.';return}",
        "v1.2.6 fast hotfix invocation")
    for key,value in [("__SCALING_RUNTIME_SHA256__",runtimehash),("__SCALING_FEEDER_SHA256__",FEEDER_SHA)]:
        runner=replace_once(runner,key,value,f"runner {key}")
    (payload/"Run-Scaling-Action.ps1").write_text(runner,encoding="utf-8")

    iss_path=repo/"installer/GTAIV-Scaling-Setup-v128.iss"
    iss=iss_path.read_text(encoding="utf-8")
    need(iss.count("1.2.6")>=8,"Unexpected Inno source version")
    iss=iss.replace("1.2.6","1.2.8")
    iss_path.write_text(iss,encoding="utf-8")
    need("1.2.6" not in iss,"Stale Inno version")
    print(f"PINNED CLIENT SHA256={TESTED_CLIENT_SHA}")
    print(f"RUNTIME ZIP SHA256={runtimehash}")
    print(f"FEEDER SHA256={FEEDER_SHA}")
    print(f"CHANGED RUNTIME FILES={sorted(changed)}")
    print(f"FOUNDATION HASH ENTRIES={n[0]}")
    print("PASS: payload and Inno sources ready")
    
if __name__=="__main__":
    main()
){return $false}
    if(-not(Test-ApprovedV127Bridge $Root)){Fail 'Installed v1.2.7 rendering files differ from the tested release. No files changed.'}
    $backup=Join-Path $Root ('_GTAIV_SCALING_PRE128_BACKUP_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    New-Item -ItemType Directory -Path $backup -Force|Out-Null
    Copy-Item -LiteralPath $receipt -Destination (Join-Path $backup 'GTAIV_SCALING_INSTALLED.txt') -Force
    $updated=[regex]::Replace($old,'(?m)^Version=1\.2\.7(?=\r?$)','Version=1.2.8')
    [IO.File]::WriteAllText($receipt,($updated.TrimEnd([char]13,[char]10)+[Environment]::NewLine+'InstallerMaintenance=1.2.8'+[Environment]::NewLine+"Pre128Backup=$backup"+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
    return $true
}
function Test-ExistingV128([string]$Root){
    $receipt=Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    if(-not(Test-Path -LiteralPath $receipt -PathType Leaf)){return $false}
    if([IO.File]::ReadAllText($receipt) -notmatch '(?m)^Version=1\.2\.8\r?
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", type=Path, required=True, help="Unpacked v1.2.6 release-prep artifact")
    ap.add_argument("--client", type=Path, required=True, help="Successful selective-mask diagnostic d3d9.dll")
    args = ap.parse_args()
    repo=Path.cwd()
    runtime_zip=args.base / "installer/payload/GTAIV-Scaling-Runtime-v1.2.6.zip"
    need(runtime_zip.is_file(), f"Missing {runtime_zip}")
    need(sha(runtime_zip.read_bytes())==BASE_RUNTIME_SHA, "Wrong v1.2.6 runtime")
    need(sha(args.client.read_bytes())==TESTED_CLIENT_SHA, "Wrong or untested bridge DLL")
    src=repo / "_runtime127"
    if src.exists(): shutil.rmtree(src)
    src.mkdir()
    with zipfile.ZipFile(runtime_zip) as archive:
        names=set(archive.namelist())
        need("d3d9.dll" in names and "bridge.conf" in names and "SHA256SUMS.txt" in names, "Bad old runtime")
        for item in archive.infolist():
            target=src / item.filename
            if item.is_dir(): target.mkdir(parents=True,exist_ok=True)
            else:
                target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(archive.read(item.filename))
    original={f.relative_to(src).as_posix():sha(f.read_bytes()) for f in src.rglob("*") if f.is_file()}
    need(sha((src/"dlss5-feed.addon64").read_bytes())==FEEDER_SHA,"Feeder mismatch")
    (src/"d3d9.dll").write_bytes(args.client.read_bytes())
    (src/"bridge.conf").write_bytes(change_config((src/"bridge.conf").read_bytes()))
    (src/"GTAIV-SCALING-VERSION.txt").write_bytes(b"GTA IV Scaling runtime 1.2.8 - pinned shader/stream state fix\n")
    hashes=[]
    for f in sorted(src.rglob("*")):
        if f.is_file() and f.name != "SHA256SUMS.txt":
            hashes.append(f"{sha(f.read_bytes())}  {f.relative_to(src).as_posix()}")
    (src/"SHA256SUMS.txt").write_text("\n".join(hashes)+"\n",encoding="ascii")
    changed=[rel for rel,old in original.items() if sha((src/rel).read_bytes())!=old]
    expected={"d3d9.dll","bridge.conf","GTAIV-SCALING-VERSION.txt","SHA256SUMS.txt"}
    need(set(changed)==expected, f"Unexpected changed runtime files: {changed}")
    config=(src/"bridge.conf").read_text(encoding="utf-8")
    for setting in ["eliminateRedundantSetterCalls = True","clientStateBatch = True","clientRedundantBypassMask = 1032192"]:
        need(setting in config, f"Missing pinned setting: {setting}")

    payload=repo/"installer/payload"
    payload.mkdir(parents=True,exist_ok=True)
    out_zip=payload/"GTAIV-Scaling-Runtime-v1.2.8.zip"
    with zipfile.ZipFile(out_zip,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in sorted(src.rglob("*")):
            if file.is_file():z.write(file,file.relative_to(src).as_posix())
    runtimehash=sha(out_zip.read_bytes())
    (payload/"GTAIV-Scaling-Runtime-v1.2.8.sha256").write_text(runtimehash+"\n",encoding="ascii")
    (payload/"dlss5-feed-v1.2.8.sha256").write_text(FEEDER_SHA+"\n",encoding="ascii")
    patch_src=args.base/"installer/payload/ReShade64-bbridge.dll"
    need(sha(patch_src.read_bytes())==RESH_PATCH_SHA,"Wrong ReShade input patch")
    shutil.copyfile(patch_src,payload/"ReShade64-bbridge.dll")

    core=(repo/"install/core/Install-DLAA-Core.bat").read_text(encoding="utf-8")
    core=replace_once(core,"A0796FA04DFACEC7997B08BEFE1933EFBB17D2BC62478CB41B8C89750674CEE3",runtimehash,"foundation runtime checksum")
    core=replace_once(core,"B6D7D9B050C4F32642A528E7700F38A0510795C7D61D30665DC96AF270B9ED27",FEEDER_SHA,"foundation feeder checksum")
    core=core.replace("GTAIV-DLSS-Setup.exe","GTAIV-Scaling-Setup-v1.2.8.exe")
    match=re.search(r"(?s)\$RuntimeHashes=@\{(.*?)\}",core)
    need(match is not None,"RuntimeHashes table missing")
    line=re.compile(r"(?m)^([ \t]*'([^']+)'[ \t]*=[ \t]*')([0-9A-Fa-f]{64})('[ \t]*;?[ \t]*\r?$)")
    n=[0]
    def replace_entry(m):
        rel=m.group(2)
        f=src/rel
        need(f.is_file(),f"Missing foundation runtime file {rel}")
        n[0]+=1
        return m.group(1)+sha(f.read_bytes())+m.group(4)
    block=line.sub(replace_entry,match.group(1))
    need(n[0]>=10,f"Only {n[0]} foundation hashes")
    core=core[:match.start(1)]+block+core[match.end(1):]
    (payload/"Install-DLAA-Core-v1.2.8.bat").write_text(core,encoding="utf-8")

    runner=(repo/"installer/Run-Scaling-Action-v128.ps1").read_text(encoding="utf-8")
    runner=replace_once(runner,"$Version='1.2.6'","$Version='1.2.8'","runner version")
    runner=runner.replace("v1.2.6","v1.2.8")
    runner=replace_once(runner,
        "if(Repair-V122AspectRatio $Root){Upgrade-AddonUi $Root;TryAutoNrUpdate $Root $NrPackage;return}",
        "# The old v1.2.2-1.2.4 config-only shortcut must NOT skip the v1.2.8 bridge DLL.",
        "old config-only shortcut")
    runner=replace_once(runner,"function Install-Scaling([string]$Root){",
        fast_upgrade()+"function Install-Scaling([string]$Root){","hotfix insertion point")
    runner=replace_once(runner,
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}",
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}\n    if(Repair-V126BridgePin $Root){Write-Result 'GTA IV Scaling 1.2.8 pinned bridge upgrade completed without modifying mods, scaling profiles or FusionFix.';return}",
        "v1.2.6 fast hotfix invocation")
    for key,value in [("__SCALING_RUNTIME_SHA256__",runtimehash),("__SCALING_FEEDER_SHA256__",FEEDER_SHA)]:
        runner=replace_once(runner,key,value,f"runner {key}")
    (payload/"Run-Scaling-Action.ps1").write_text(runner,encoding="utf-8")

    iss_path=repo/"installer/GTAIV-Scaling-Setup-v128.iss"
    iss=iss_path.read_text(encoding="utf-8")
    need(iss.count("1.2.6")>=8,"Unexpected Inno source version")
    iss=iss.replace("1.2.6","1.2.8")
    iss_path.write_text(iss,encoding="utf-8")
    need("1.2.6" not in iss,"Stale Inno version")
    print(f"PINNED CLIENT SHA256={TESTED_CLIENT_SHA}")
    print(f"RUNTIME ZIP SHA256={runtimehash}")
    print(f"FEEDER SHA256={FEEDER_SHA}")
    print(f"CHANGED RUNTIME FILES={sorted(changed)}")
    print(f"FOUNDATION HASH ENTRIES={n[0]}")
    print("PASS: payload and Inno sources ready")
    
if __name__=="__main__":
    main()
){return $false}
    if(-not(Test-ApprovedV127Bridge $Root)){Fail 'Existing 1.2.8 renderer differs from the approved pin; refusing to overwrite.'}
    return $true
}
'''

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", type=Path, required=True, help="Unpacked v1.2.6 release-prep artifact")
    ap.add_argument("--client", type=Path, required=True, help="Successful selective-mask diagnostic d3d9.dll")
    args = ap.parse_args()
    repo=Path.cwd()
    runtime_zip=args.base / "installer/payload/GTAIV-Scaling-Runtime-v1.2.6.zip"
    need(runtime_zip.is_file(), f"Missing {runtime_zip}")
    need(sha(runtime_zip.read_bytes())==BASE_RUNTIME_SHA, "Wrong v1.2.6 runtime")
    need(sha(args.client.read_bytes())==TESTED_CLIENT_SHA, "Wrong or untested bridge DLL")
    src=repo / "_runtime127"
    if src.exists(): shutil.rmtree(src)
    src.mkdir()
    with zipfile.ZipFile(runtime_zip) as archive:
        names=set(archive.namelist())
        need("d3d9.dll" in names and "bridge.conf" in names and "SHA256SUMS.txt" in names, "Bad old runtime")
        for item in archive.infolist():
            target=src / item.filename
            if item.is_dir(): target.mkdir(parents=True,exist_ok=True)
            else:
                target.parent.mkdir(parents=True,exist_ok=True)
                target.write_bytes(archive.read(item.filename))
    original={f.relative_to(src).as_posix():sha(f.read_bytes()) for f in src.rglob("*") if f.is_file()}
    need(sha((src/"dlss5-feed.addon64").read_bytes())==FEEDER_SHA,"Feeder mismatch")
    (src/"d3d9.dll").write_bytes(args.client.read_bytes())
    (src/"bridge.conf").write_bytes(change_config((src/"bridge.conf").read_bytes()))
    (src/"GTAIV-SCALING-VERSION.txt").write_bytes(b"GTA IV Scaling runtime 1.2.8 - pinned shader/stream state fix\n")
    hashes=[]
    for f in sorted(src.rglob("*")):
        if f.is_file() and f.name != "SHA256SUMS.txt":
            hashes.append(f"{sha(f.read_bytes())}  {f.relative_to(src).as_posix()}")
    (src/"SHA256SUMS.txt").write_text("\n".join(hashes)+"\n",encoding="ascii")
    changed=[rel for rel,old in original.items() if sha((src/rel).read_bytes())!=old]
    expected={"d3d9.dll","bridge.conf","GTAIV-SCALING-VERSION.txt","SHA256SUMS.txt"}
    need(set(changed)==expected, f"Unexpected changed runtime files: {changed}")
    config=(src/"bridge.conf").read_text(encoding="utf-8")
    for setting in ["eliminateRedundantSetterCalls = True","clientStateBatch = True","clientRedundantBypassMask = 1032192"]:
        need(setting in config, f"Missing pinned setting: {setting}")

    payload=repo/"installer/payload"
    payload.mkdir(parents=True,exist_ok=True)
    out_zip=payload/"GTAIV-Scaling-Runtime-v1.2.8.zip"
    with zipfile.ZipFile(out_zip,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in sorted(src.rglob("*")):
            if file.is_file():z.write(file,file.relative_to(src).as_posix())
    runtimehash=sha(out_zip.read_bytes())
    (payload/"GTAIV-Scaling-Runtime-v1.2.8.sha256").write_text(runtimehash+"\n",encoding="ascii")
    (payload/"dlss5-feed-v1.2.8.sha256").write_text(FEEDER_SHA+"\n",encoding="ascii")
    patch_src=args.base/"installer/payload/ReShade64-bbridge.dll"
    need(sha(patch_src.read_bytes())==RESH_PATCH_SHA,"Wrong ReShade input patch")
    shutil.copyfile(patch_src,payload/"ReShade64-bbridge.dll")

    core=(repo/"install/core/Install-DLAA-Core.bat").read_text(encoding="utf-8")
    core=replace_once(core,"A0796FA04DFACEC7997B08BEFE1933EFBB17D2BC62478CB41B8C89750674CEE3",runtimehash,"foundation runtime checksum")
    core=replace_once(core,"B6D7D9B050C4F32642A528E7700F38A0510795C7D61D30665DC96AF270B9ED27",FEEDER_SHA,"foundation feeder checksum")
    core=core.replace("GTAIV-DLSS-Setup.exe","GTAIV-Scaling-Setup-v1.2.8.exe")
    match=re.search(r"(?s)\$RuntimeHashes=@\{(.*?)\}",core)
    need(match is not None,"RuntimeHashes table missing")
    line=re.compile(r"(?m)^([ \t]*'([^']+)'[ \t]*=[ \t]*')([0-9A-Fa-f]{64})('[ \t]*;?[ \t]*\r?$)")
    n=[0]
    def replace_entry(m):
        rel=m.group(2)
        f=src/rel
        need(f.is_file(),f"Missing foundation runtime file {rel}")
        n[0]+=1
        return m.group(1)+sha(f.read_bytes())+m.group(4)
    block=line.sub(replace_entry,match.group(1))
    need(n[0]>=10,f"Only {n[0]} foundation hashes")
    core=core[:match.start(1)]+block+core[match.end(1):]
    (payload/"Install-DLAA-Core-v1.2.8.bat").write_text(core,encoding="utf-8")

    runner=(repo/"installer/Run-Scaling-Action-v128.ps1").read_text(encoding="utf-8")
    runner=replace_once(runner,"$Version='1.2.6'","$Version='1.2.8'","runner version")
    runner=runner.replace("v1.2.6","v1.2.8")
    runner=replace_once(runner,
        "if(Repair-V122AspectRatio $Root){Upgrade-AddonUi $Root;TryAutoNrUpdate $Root $NrPackage;return}",
        "# The old v1.2.2-1.2.4 config-only shortcut must NOT skip the v1.2.8 bridge DLL.",
        "old config-only shortcut")
    runner=replace_once(runner,"function Install-Scaling([string]$Root){",
        fast_upgrade()+"function Install-Scaling([string]$Root){","hotfix insertion point")
    runner=replace_once(runner,
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}",
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}\n    if(Repair-V126BridgePin $Root){Write-Result 'GTA IV Scaling 1.2.8 pinned bridge upgrade completed without modifying mods, scaling profiles or FusionFix.';return}",
        "v1.2.6 fast hotfix invocation")
    for key,value in [("__SCALING_RUNTIME_SHA256__",runtimehash),("__SCALING_FEEDER_SHA256__",FEEDER_SHA)]:
        runner=replace_once(runner,key,value,f"runner {key}")
    (payload/"Run-Scaling-Action.ps1").write_text(runner,encoding="utf-8")

    iss_path=repo/"installer/GTAIV-Scaling-Setup-v128.iss"
    iss=iss_path.read_text(encoding="utf-8")
    need(iss.count("1.2.6")>=8,"Unexpected Inno source version")
    iss=iss.replace("1.2.6","1.2.8")
    iss_path.write_text(iss,encoding="utf-8")
    need("1.2.6" not in iss,"Stale Inno version")
    print(f"PINNED CLIENT SHA256={TESTED_CLIENT_SHA}")
    print(f"RUNTIME ZIP SHA256={runtimehash}")
    print(f"FEEDER SHA256={FEEDER_SHA}")
    print(f"CHANGED RUNTIME FILES={sorted(changed)}")
    print(f"FOUNDATION HASH ENTRIES={n[0]}")
    print("PASS: payload and Inno sources ready")
    
if __name__=="__main__":
    main()
