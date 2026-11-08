#!/usr/bin/env python3
"""Build v1.2.9 using the exact user-validated bridge DLL and v1.2.6 runtime.

No rendering DLL, feeder, DXVK or FusionFix components are recompiled. The
only changed runtime content is the pinned b-bridge client and its config.
"""
import argparse
import hashlib
import io
import re
import shutil
import struct
import zipfile
from pathlib import Path

VERSION = "1.2.9"
BASE_RUNTIME_SHA = "44960556C6643D48158B57F8B23659E152879FFD2B5591C3C8E323ACA91DD6FB"
TESTED_CLIENT_SHA = "B2FE0313971080A7D5D011BC047F66A8E540FC55B9C279A81A3A9CB9D4EEFDDF"
FEEDER_SHA = "C8C7D555F6E1BFBA939560DB3F641BA64FC480D07E9A2C193E0CD468FC026550"
RESH_PATCH_SHA = "D5BD8CB2B6E935506888EA71711361B9AFCD72ED7C70926C0F52E8F8E47C7510"
UPSTREAM_COMPAT_ZIP_SHA = "0482092C0A64083FC5E4233E92656210D71802D2C2D1AAEF83BB01E97D6C778F"

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
# Check the exact verified renderer rather than reinstalling it.
function Test-ApprovedV127Bridge([string]$Root){
    $receipt=Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    $dll=Join-Path $Root 'd3d9.dll'
    $config=Join-Path $Root '.trex\bridge.conf'
    if(-not(Test-Foundation $Root) -or -not(Test-Path -LiteralPath $receipt -PathType Leaf) -or
       -not(Test-Path -LiteralPath $dll -PathType Leaf) -or
       -not(Test-Path -LiteralPath $config -PathType Leaf)){return $false}
    if((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToUpperInvariant() -ne
       'B2FE0313971080A7D5D011BC047F66A8E540FC55B9C279A81A3A9CB9D4EEFDDF'){return $false}
    return ([IO.File]::ReadAllText($config) -match '(?m)^\s*clientRedundantBypassMask\s*=\s*1032192\s*$')
}
function Repair-V127InstallerOnly([string]$Root){
    $receipt=Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    if(-not(Test-Path -LiteralPath $receipt -PathType Leaf)){return $false}
    $old=[IO.File]::ReadAllText($receipt)
    if($old -notmatch '(?m)^Version=1\.2\.7\r?$'){return $false}
    if(-not(Test-ApprovedV127Bridge $Root)){Fail 'Installed v1.2.7 renderer differs from tested release. No files changed.'}
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

def is_pe_i386(data):
    need(len(data) > 0x40 and data[:2] == b"MZ", "Compatibility ASI is not a PE executable")
    pe_offset = struct.unpack_from("<I", data, 0x3C)[0]
    need(data[pe_offset:pe_offset+4] == b"PE\0\0", "Compatibility ASI has an invalid PE header")
    machine = struct.unpack_from("<H", data, pe_offset+4)[0]
    need(machine == 0x14C, f"Compatibility ASI must be 32-bit x86, got machine 0x{machine:04X}")
    return True

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", type=Path, required=True, help="Unpacked v1.2.6 release-prep artifact")
    ap.add_argument("--client", type=Path, required=True, help="Successful selective-mask diagnostic d3d9.dll")
    ap.add_argument("--compat-archive", type=Path, required=True, help="Official upstream GTAIV compatibility mod 1.7.3 ZIP")
    args = ap.parse_args()
    repo=Path.cwd()
    runtime_zip=args.base / "installer/payload/GTAIV-Scaling-Runtime-v1.2.6.zip"
    need(runtime_zip.is_file(), f"Missing {runtime_zip}")
    need(sha(runtime_zip.read_bytes())==BASE_RUNTIME_SHA, "Wrong v1.2.6 runtime")
    need(sha(args.client.read_bytes())==TESTED_CLIENT_SHA, "Wrong or untested bridge DLL")
    need(args.compat_archive.is_file(), f"Missing upstream compatibility archive: {args.compat_archive}")
    need(sha(args.compat_archive.read_bytes())==UPSTREAM_COMPAT_ZIP_SHA, "Wrong upstream GTA IV compatibility mod 1.7.3 archive")
    with zipfile.ZipFile(args.compat_archive) as upstream:
        compat_name = "GTAIV-Remix-CompatibilityMod/a_gta4-rtx.asi"
        need(compat_name in upstream.namelist(), f"Missing {compat_name} in upstream archive")
        compat_bytes = upstream.read(compat_name)
    is_pe_i386(compat_bytes)
    need(1024 * 1024 < len(compat_bytes) < 100 * 1024 * 1024, "Unexpected compatibility ASI size")
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
    (src/"GTAIV-SCALING-VERSION.txt").write_bytes(b"GTA IV Scaling runtime 1.2.9 - pinned shader/stream state fix\n")
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
    compat_asi = payload/"a_gta4-rtx-1.7.3.asi"
    compat_asi.write_bytes(compat_bytes)
    compatibility_hash = sha(compat_bytes)
    (payload/"a_gta4-rtx-v1.7.3.sha256").write_text(compatibility_hash+"\n",encoding="ascii")
    out_zip=payload/"GTAIV-Scaling-Runtime-v1.2.9.zip"
    with zipfile.ZipFile(out_zip,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in sorted(src.rglob("*")):
            if file.is_file():z.write(file,file.relative_to(src).as_posix())
    runtimehash=sha(out_zip.read_bytes())
    (payload/"GTAIV-Scaling-Runtime-v1.2.9.sha256").write_text(runtimehash+"\n",encoding="ascii")
    (payload/"dlss5-feed-v1.2.9.sha256").write_text(FEEDER_SHA+"\n",encoding="ascii")
    patch_src=args.base/"installer/payload/ReShade64-bbridge.dll"
    need(sha(patch_src.read_bytes())==RESH_PATCH_SHA,"Wrong ReShade input patch")
    shutil.copyfile(patch_src,payload/"ReShade64-bbridge.dll")

    core=(repo/"install/core/Install-DLAA-Core.bat").read_text(encoding="utf-8")
    core=replace_once(core,"A0796FA04DFACEC7997B08BEFE1933EFBB17D2BC62478CB41B8C89750674CEE3",runtimehash,"foundation runtime checksum")
    core=replace_once(core,"B6D7D9B050C4F32642A528E7700F38A0510795C7D61D30665DC96AF270B9ED27",FEEDER_SHA,"foundation feeder checksum")
    core=core.replace("GTAIV-DLSS-Setup.exe","GTAIV-Scaling-Setup-v1.2.9.exe")
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
    (payload/"Install-DLAA-Core-v1.2.9.bat").write_text(core,encoding="utf-8")

    runner=(repo/"installer/Run-Scaling-Action-v129.ps1").read_text(encoding="utf-8")
    runner=replace_once(runner,"$Version='1.2.6'","$Version='1.2.9'","runner version")
    runner=runner.replace("v1.2.6","v1.2.9")
    runner=replace_once(runner,
        "if(Repair-V122AspectRatio $Root){Upgrade-AddonUi $Root;TryAutoNrUpdate $Root $NrPackage;return}",
        "# The old v1.2.2-1.2.4 config-only shortcut must NOT skip the v1.2.9 bridge DLL.",
        "old config-only shortcut")
    runner=replace_once(runner,"function Install-Scaling([string]$Root){",
        fast_upgrade()+maintenance_fast_path()+"function Install-Scaling([string]$Root){","hotfix insertion point")
    runner=replace_once(runner,
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}",
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}\n" +
        "    if(Test-ExistingV129 $Root){$compat=Install-CompatibilityAsi $Root;Write-CompatibilityReceipt $Root $compat;if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'Already on v1.2.9; Social Club compatibility verified and graphics preserved.';return}\n" +
        "    if(Test-ExistingV128 $Root){$compat=Install-CompatibilityAsi $Root;Write-CompatibilityReceipt $Root $compat;if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'v1.2.8 upgraded to 1.2.9 with Social Club overlay fix; graphics preserved.';return}\n" +
        "    if(Repair-V127InstallerOnly $Root){$compat=Install-CompatibilityAsi $Root;Write-CompatibilityReceipt $Root $compat;if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'v1.2.7 upgraded to 1.2.9; graphics preserved.';return}\n" +
        "    if(Repair-V126BridgePin $Root){$compat=Install-CompatibilityAsi $Root;Write-CompatibilityReceipt $Root $compat;if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'v1.2.6 upgraded to 1.2.9; Social Club overlay fix installed.';return}",
        "v1.2.6 fast hotfix invocation")
    for key,value in [("__SCALING_RUNTIME_SHA256__",runtimehash),("__SCALING_FEEDER_SHA256__",FEEDER_SHA),("__COMPATIBILITY_ASI_SHA256__",compatibility_hash)]:
        runner=replace_once(runner,key,value,f"runner {key}")
    (payload/"Run-Scaling-Action.ps1").write_text(runner,encoding="utf-8")

    iss_path=repo/"installer/GTAIV-Scaling-Setup-v129.iss"
    iss=iss_path.read_text(encoding="utf-8")
    need(iss.count("1.2.6")>=8,"Unexpected Inno source version")
    iss=iss.replace("1.2.6","1.2.9")
    iss_path.write_text(iss,encoding="utf-8")
    need("1.2.6" not in iss,"Stale Inno version")
    print(f"PINNED CLIENT SHA256={TESTED_CLIENT_SHA}")
    print(f"RUNTIME ZIP SHA256={runtimehash}")
    print(f"FEEDER SHA256={FEEDER_SHA}")
    print(f"COMPATIBILITY ASI 1.7.3 SHA256={compatibility_hash}")
    print(f"CHANGED RUNTIME FILES={sorted(changed)}")
    print(f"FOUNDATION HASH ENTRIES={n[0]}")
    print("PASS: payload and Inno sources ready")
    
if __name__=="__main__":
    main()
){return $false}
    if(-not(Test-ApprovedV127Bridge $Root)){Fail 'Installed 1.2.9 renderer differs from approved pin; refusing to overwrite.'}
    return $true
}
function Test-ExistingV129([string]$Root){
    $receipt=Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    if(-not(Test-Path -LiteralPath $receipt -PathType Leaf)){return $false}
    if([IO.File]::ReadAllText($receipt) -notmatch '(?m)^Version=1\.2\.9\r?

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
    (src/"GTAIV-SCALING-VERSION.txt").write_bytes(b"GTA IV Scaling runtime 1.2.9 - pinned shader/stream state fix\n")
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
    out_zip=payload/"GTAIV-Scaling-Runtime-v1.2.9.zip"
    with zipfile.ZipFile(out_zip,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in sorted(src.rglob("*")):
            if file.is_file():z.write(file,file.relative_to(src).as_posix())
    runtimehash=sha(out_zip.read_bytes())
    (payload/"GTAIV-Scaling-Runtime-v1.2.9.sha256").write_text(runtimehash+"\n",encoding="ascii")
    (payload/"dlss5-feed-v1.2.9.sha256").write_text(FEEDER_SHA+"\n",encoding="ascii")
    patch_src=args.base/"installer/payload/ReShade64-bbridge.dll"
    need(sha(patch_src.read_bytes())==RESH_PATCH_SHA,"Wrong ReShade input patch")
    shutil.copyfile(patch_src,payload/"ReShade64-bbridge.dll")

    core=(repo/"install/core/Install-DLAA-Core.bat").read_text(encoding="utf-8")
    core=replace_once(core,"A0796FA04DFACEC7997B08BEFE1933EFBB17D2BC62478CB41B8C89750674CEE3",runtimehash,"foundation runtime checksum")
    core=replace_once(core,"B6D7D9B050C4F32642A528E7700F38A0510795C7D61D30665DC96AF270B9ED27",FEEDER_SHA,"foundation feeder checksum")
    core=core.replace("GTAIV-DLSS-Setup.exe","GTAIV-Scaling-Setup-v1.2.9.exe")
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
    (payload/"Install-DLAA-Core-v1.2.9.bat").write_text(core,encoding="utf-8")

    runner=(repo/"installer/Run-Scaling-Action-v128.ps1").read_text(encoding="utf-8")
    runner=replace_once(runner,"$Version='1.2.6'","$Version='1.2.9'","runner version")
    runner=runner.replace("v1.2.6","v1.2.9")
    runner=replace_once(runner,
        "if(Repair-V122AspectRatio $Root){Upgrade-AddonUi $Root;TryAutoNrUpdate $Root $NrPackage;return}",
        "# The old v1.2.2-1.2.4 config-only shortcut must NOT skip the v1.2.9 bridge DLL.",
        "old config-only shortcut")
    runner=replace_once(runner,"function Install-Scaling([string]$Root){",
        fast_upgrade()+maintenance_fast_path()+"function Install-Scaling([string]$Root){","hotfix insertion point")
    runner=replace_once(runner,
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}",
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}\n" +
        "    if(Test-ExistingV128 $Root){if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'Already on v1.2.9, graphics preserved.';return}\n" +
        "    if(Repair-V127InstallerOnly $Root){if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'v1.2.9 installer-only maintenance, graphics preserved.';return}\n" +
        "    if(Repair-V126BridgePin $Root){if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'v1.2.6 upgraded with approved bridge pin; NR choice processed.';return}",
        "v1.2.6 fast hotfix invocation")
    for key,value in [("__SCALING_RUNTIME_SHA256__",runtimehash),("__SCALING_FEEDER_SHA256__",FEEDER_SHA)]:
        runner=replace_once(runner,key,value,f"runner {key}")
    (payload/"Run-Scaling-Action.ps1").write_text(runner,encoding="utf-8")

    iss_path=repo/"installer/GTAIV-Scaling-Setup-v128.iss"
    iss=iss_path.read_text(encoding="utf-8")
    need(iss.count("1.2.6")>=8,"Unexpected Inno source version")
    iss=iss.replace("1.2.6","1.2.9")
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
    if(-not(Test-ApprovedV127Bridge $Root)){Fail 'Installed 1.2.9 renderer differs from approved pin; refusing to overwrite.'}
    return $true
}
function Get-ReceiptValue([string]$Text,[string]$Key){
    $m=[regex]::Match($Text,'(?m)^'+[regex]::Escape($Key)+'=(.*)

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
    (src/"GTAIV-SCALING-VERSION.txt").write_bytes(b"GTA IV Scaling runtime 1.2.9 - pinned shader/stream state fix\n")
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
    out_zip=payload/"GTAIV-Scaling-Runtime-v1.2.9.zip"
    with zipfile.ZipFile(out_zip,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in sorted(src.rglob("*")):
            if file.is_file():z.write(file,file.relative_to(src).as_posix())
    runtimehash=sha(out_zip.read_bytes())
    (payload/"GTAIV-Scaling-Runtime-v1.2.9.sha256").write_text(runtimehash+"\n",encoding="ascii")
    (payload/"dlss5-feed-v1.2.9.sha256").write_text(FEEDER_SHA+"\n",encoding="ascii")
    patch_src=args.base/"installer/payload/ReShade64-bbridge.dll"
    need(sha(patch_src.read_bytes())==RESH_PATCH_SHA,"Wrong ReShade input patch")
    shutil.copyfile(patch_src,payload/"ReShade64-bbridge.dll")

    core=(repo/"install/core/Install-DLAA-Core.bat").read_text(encoding="utf-8")
    core=replace_once(core,"A0796FA04DFACEC7997B08BEFE1933EFBB17D2BC62478CB41B8C89750674CEE3",runtimehash,"foundation runtime checksum")
    core=replace_once(core,"B6D7D9B050C4F32642A528E7700F38A0510795C7D61D30665DC96AF270B9ED27",FEEDER_SHA,"foundation feeder checksum")
    core=core.replace("GTAIV-DLSS-Setup.exe","GTAIV-Scaling-Setup-v1.2.9.exe")
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
    (payload/"Install-DLAA-Core-v1.2.9.bat").write_text(core,encoding="utf-8")

    runner=(repo/"installer/Run-Scaling-Action-v128.ps1").read_text(encoding="utf-8")
    runner=replace_once(runner,"$Version='1.2.6'","$Version='1.2.9'","runner version")
    runner=runner.replace("v1.2.6","v1.2.9")
    runner=replace_once(runner,
        "if(Repair-V122AspectRatio $Root){Upgrade-AddonUi $Root;TryAutoNrUpdate $Root $NrPackage;return}",
        "# The old v1.2.2-1.2.4 config-only shortcut must NOT skip the v1.2.9 bridge DLL.",
        "old config-only shortcut")
    runner=replace_once(runner,"function Install-Scaling([string]$Root){",
        fast_upgrade()+maintenance_fast_path()+"function Install-Scaling([string]$Root){","hotfix insertion point")
    runner=replace_once(runner,
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}",
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}\n" +
        "    if(Test-ExistingV128 $Root){if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'Already on v1.2.9, graphics preserved.';return}\n" +
        "    if(Repair-V127InstallerOnly $Root){if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'v1.2.9 installer-only maintenance, graphics preserved.';return}\n" +
        "    if(Repair-V126BridgePin $Root){if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'v1.2.6 upgraded with approved bridge pin; NR choice processed.';return}",
        "v1.2.6 fast hotfix invocation")
    for key,value in [("__SCALING_RUNTIME_SHA256__",runtimehash),("__SCALING_FEEDER_SHA256__",FEEDER_SHA)]:
        runner=replace_once(runner,key,value,f"runner {key}")
    (payload/"Run-Scaling-Action.ps1").write_text(runner,encoding="utf-8")

    iss_path=repo/"installer/GTAIV-Scaling-Setup-v128.iss"
    iss=iss_path.read_text(encoding="utf-8")
    need(iss.count("1.2.6")>=8,"Unexpected Inno source version")
    iss=iss.replace("1.2.6","1.2.9")
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
    if($m.Success){return $m.Groups[1].Value.Trim()}
    return ''
}
function Install-CompatibilityAsi([string]$Root){
    if(-not $CompatibilityAsi -or -not(Test-Path -LiteralPath $CompatibilityAsi -PathType Leaf)){
        Fail 'The upstream GTA IV 1.7.3 compatibility ASI is missing from setup.'
    }
    Assert-SHA256 $CompatibilityAsi $CompatibilityAsiHash 'GTA IV compatibility mod 1.7.3'
    $target=Join-Path $Root 'a_gta4-rtx.asi'
    $currentHash=''
    if(Test-Path -LiteralPath $target -PathType Leaf){
        $currentHash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToUpperInvariant()
    }
    $receipt=Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    $oldText=if(Test-Path -LiteralPath $receipt -PathType Leaf){[IO.File]::ReadAllText($receipt)}else{''}
    if($currentHash -eq $CompatibilityAsiHash){
        return [pscustomobject]@{
            Managed=(Get-ReceiptValue $oldText 'CompatibilityAsiManaged')
            BackupPath=(Get-ReceiptValue $oldText 'CompatibilityAsiBackup')
            OriginalPresent=(Get-ReceiptValue $oldText 'CompatibilityAsiOriginalPresent')
            OriginalHash=(Get-ReceiptValue $oldText 'CompatibilityAsiOriginalHash')
            InstalledHash=$CompatibilityAsiHash
        }
    }
    $backup=Join-Path $Root ('_GTAIV_SCALING_PRE129_BACKUP_'+(Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
    New-Item -ItemType Directory -Path $backup -Force|Out-Null
    $originalPresent=Test-Path -LiteralPath $target -PathType Leaf
    $originalHash=''
    if($originalPresent){
        $originalHash=$currentHash
        Copy-Item -LiteralPath $target -Destination (Join-Path $backup 'a_gta4-rtx.asi') -Force
        if((Get-FileHash -LiteralPath (Join-Path $backup 'a_gta4-rtx.asi') -Algorithm SHA256).Hash.ToUpperInvariant() -ne $originalHash){
            Fail 'Could not verify the backup of the existing a_gta4-rtx.asi. The original file was not replaced.'
        }
    }
    $info=[pscustomobject]@{
        Managed='1'
        BackupPath=$backup
        OriginalPresent=$(if($originalPresent){'1'}else{'0'})
        OriginalHash=$originalHash
        InstalledHash=$CompatibilityAsiHash
    }
    $temporary=$target+'.gtaiv-scaling-new'
    try{
        Copy-Item -LiteralPath $CompatibilityAsi -Destination $temporary -Force
        Assert-SHA256 $temporary $CompatibilityAsiHash 'staged GTA IV compatibility ASI 1.7.3'
        Move-Item -LiteralPath $temporary -Destination $target -Force
        Assert-SHA256 $target $CompatibilityAsiHash 'installed GTA IV compatibility ASI 1.7.3'
        Write-CompatibilityReceipt $Root $info
    }catch{
        Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        if($originalPresent){Copy-Item -LiteralPath (Join-Path $backup 'a_gta4-rtx.asi') -Destination $target -Force}
        elseif(Test-Path -LiteralPath $target){Remove-Item -LiteralPath $target -Force}
        throw
    }
    Write-Host 'Installed upstream GTA IV compatibility mod 1.7.3 (Social Club overlay device fix).' -ForegroundColor Green
    return $info
}
function Write-CompatibilityReceipt([string]$Root,[object]$Info){
    $receipt=Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    if(-not(Test-Path -LiteralPath $receipt -PathType Leaf)){Fail 'Scaling receipt is missing while recording compatibility ASI state.'}
    $values=[ordered]@{
        CompatibilityAsiVersion='1.7.3'
        CompatibilityAsiManaged=[string]$Info.Managed
        CompatibilityAsiInstalledHash=[string]$Info.InstalledHash
        CompatibilityAsiOriginalPresent=[string]$Info.OriginalPresent
        CompatibilityAsiOriginalHash=[string]$Info.OriginalHash
        CompatibilityAsiBackup=[string]$Info.BackupPath
    }
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $seen=@{}
    foreach($line in [IO.File]::ReadAllLines($receipt)){
        if($line -match '^([^=]+)='){
            $key=$Matches[1]
            if($values.Contains($key)){
                [void]$lines.Add($key+'='+$values[$key])
                $seen[$key]=$true
                continue
            }
            if($key -eq 'Version'){
                [void]$lines.Add('Version=1.2.9')
                continue
            }
        }
        [void]$lines.Add($line)
    }
    foreach($key in $values.Keys){
        if(-not $seen.ContainsKey($key)){[void]$lines.Add($key+'='+$values[$key])}
    }
    $temporary=$receipt+'.gtaiv-scaling-receipt.tmp'
    [IO.File]::WriteAllLines($temporary,$lines.ToArray(),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $receipt -Force
}
function Restore-CompatibilityAsi([string]$Root){
    $receipt=Join-Path $Root 'GTAIV_SCALING_INSTALLED.txt'
    if(-not(Test-Path -LiteralPath $receipt -PathType Leaf)){return}
    $text=[IO.File]::ReadAllText($receipt)
    if((Get-ReceiptValue $text 'CompatibilityAsiManaged') -ne '1'){return}
    $target=Join-Path $Root 'a_gta4-rtx.asi'
    $installedHash=Get-ReceiptValue $text 'CompatibilityAsiInstalledHash'
    $currentHash=''
    if(Test-Path -LiteralPath $target -PathType Leaf){$currentHash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToUpperInvariant()}
    if($currentHash -and $currentHash -ne $installedHash){
        Write-Warning 'a_gta4-rtx.asi was modified after installation; preserving the current file instead of overwriting user changes.'
        return
    }
    if((Get-ReceiptValue $text 'CompatibilityAsiOriginalPresent') -eq '1'){
        $backupDir=Get-ReceiptValue $text 'CompatibilityAsiBackup'
        if(-not $backupDir){Fail 'The original compatibility ASI backup path is missing; refusing to uninstall.'}
        $rootFull=[IO.Path]::GetFullPath($Root).TrimEnd('\')+'\'
        $backupFull=[IO.Path]::GetFullPath($backupDir)
        if(-not $backupFull.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)){
            Fail 'Compatibility ASI backup path is outside the GTA IV folder; refusing to restore it.'
        }
        $backupFile=Join-Path $backupFull 'a_gta4-rtx.asi'
        if(-not(Test-Path -LiteralPath $backupFile -PathType Leaf)){Fail 'Original a_gta4-rtx.asi backup is missing; refusing to uninstall.'}
        $originalHash=Get-ReceiptValue $text 'CompatibilityAsiOriginalHash'
        Assert-SHA256 $backupFile $originalHash 'original compatibility ASI backup'
        Copy-Item -LiteralPath $backupFile -Destination $target -Force
        Assert-SHA256 $target $originalHash 'restored original compatibility ASI'
    }elseif($currentHash -eq $installedHash){
        Remove-Item -LiteralPath $target -Force
    }
    Write-Host 'Restored the pre-install a_gta4-rtx.asi state.' -ForegroundColor Green
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
    (src/"GTAIV-SCALING-VERSION.txt").write_bytes(b"GTA IV Scaling runtime 1.2.9 - pinned shader/stream state fix\n")
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
    out_zip=payload/"GTAIV-Scaling-Runtime-v1.2.9.zip"
    with zipfile.ZipFile(out_zip,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
        for file in sorted(src.rglob("*")):
            if file.is_file():z.write(file,file.relative_to(src).as_posix())
    runtimehash=sha(out_zip.read_bytes())
    (payload/"GTAIV-Scaling-Runtime-v1.2.9.sha256").write_text(runtimehash+"\n",encoding="ascii")
    (payload/"dlss5-feed-v1.2.9.sha256").write_text(FEEDER_SHA+"\n",encoding="ascii")
    patch_src=args.base/"installer/payload/ReShade64-bbridge.dll"
    need(sha(patch_src.read_bytes())==RESH_PATCH_SHA,"Wrong ReShade input patch")
    shutil.copyfile(patch_src,payload/"ReShade64-bbridge.dll")

    core=(repo/"install/core/Install-DLAA-Core.bat").read_text(encoding="utf-8")
    core=replace_once(core,"A0796FA04DFACEC7997B08BEFE1933EFBB17D2BC62478CB41B8C89750674CEE3",runtimehash,"foundation runtime checksum")
    core=replace_once(core,"B6D7D9B050C4F32642A528E7700F38A0510795C7D61D30665DC96AF270B9ED27",FEEDER_SHA,"foundation feeder checksum")
    core=core.replace("GTAIV-DLSS-Setup.exe","GTAIV-Scaling-Setup-v1.2.9.exe")
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
    (payload/"Install-DLAA-Core-v1.2.9.bat").write_text(core,encoding="utf-8")

    runner=(repo/"installer/Run-Scaling-Action-v128.ps1").read_text(encoding="utf-8")
    runner=replace_once(runner,"$Version='1.2.6'","$Version='1.2.9'","runner version")
    runner=runner.replace("v1.2.6","v1.2.9")
    runner=replace_once(runner,
        "if(Repair-V122AspectRatio $Root){Upgrade-AddonUi $Root;TryAutoNrUpdate $Root $NrPackage;return}",
        "# The old v1.2.2-1.2.4 config-only shortcut must NOT skip the v1.2.9 bridge DLL.",
        "old config-only shortcut")
    runner=replace_once(runner,"function Install-Scaling([string]$Root){",
        fast_upgrade()+maintenance_fast_path()+"function Install-Scaling([string]$Root){","hotfix insertion point")
    runner=replace_once(runner,
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}",
        "if(Get-Process NvRemixBridge -ErrorAction SilentlyContinue){Fail 'Close NvRemixBridge.exe before installing.'}\n" +
        "    if(Test-ExistingV128 $Root){if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'Already on v1.2.9, graphics preserved.';return}\n" +
        "    if(Repair-V127InstallerOnly $Root){if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'v1.2.9 installer-only maintenance, graphics preserved.';return}\n" +
        "    if(Repair-V126BridgePin $Root){if($NrMode -ne 'skip' -and $gpu.Series -in @(20,30,40,50)){TryAutoNrUpdate $Root $NrPackage};Write-Result 'v1.2.6 upgraded with approved bridge pin; NR choice processed.';return}",
        "v1.2.6 fast hotfix invocation")
    for key,value in [("__SCALING_RUNTIME_SHA256__",runtimehash),("__SCALING_FEEDER_SHA256__",FEEDER_SHA)]:
        runner=replace_once(runner,key,value,f"runner {key}")
    (payload/"Run-Scaling-Action.ps1").write_text(runner,encoding="utf-8")

    iss_path=repo/"installer/GTAIV-Scaling-Setup-v128.iss"
    iss=iss_path.read_text(encoding="utf-8")
    need(iss.count("1.2.6")>=8,"Unexpected Inno source version")
    iss=iss.replace("1.2.6","1.2.9")
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
