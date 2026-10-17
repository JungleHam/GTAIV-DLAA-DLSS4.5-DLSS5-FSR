[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$FeederSource)
$ErrorActionPreference='Stop'
if(-not(Test-Path -LiteralPath $FeederSource)){throw 'Feeder source not found.'}
$feed=[IO.File]::ReadAllText($FeederSource)
function Once([string]$old,[string]$new,[string]$label){
    $n=([regex]::Matches($script:feed,[regex]::Escape($old))).Count
    if($n-ne1){throw "Version-overlay $label expected one anchor, got $n"}
    $script:feed=$script:feed.Replace($old,$new)
}
$oldName='extern "C" __declspec(dllexport) const char *NAME = "GTA IV Scaling 1.2.2";'
$newName='extern "C" __declspec(dllexport) const char *NAME = "GTA IV Scaling 1.2.5";'
Once $oldName $newName 'addon title'
$helper=@'
#include <winver.h>
#include <vector>
struct M3kDllVersion { DWORD ms=0,ls=0; ULONGLONG bytes=0; bool valid=false; };
static M3kDllVersion M3kVersionOfInstalledDll(const wchar_t *file)
{
    M3kDllVersion v={};
    HMODULE self=nullptr;
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&M3kVersionOfInstalledDll),&self))return v;
    wchar_t path[MAX_PATH]={};
    if(!GetModuleFileNameW(self,path,MAX_PATH))return v;
    wchar_t *slash=wcsrchr(path,L'\\');
    if(!slash)return v;
    *(slash+1)=0;
    if(wcscat_s(path,MAX_PATH,file))return v;
    WIN32_FILE_ATTRIBUTE_DATA attr={};
    if(GetFileAttributesExW(path,GetFileExInfoStandard,&attr))
        v.bytes=(static_cast<ULONGLONG>(attr.nFileSizeHigh)<<32)|attr.nFileSizeLow;
    DWORD ignored=0;
    DWORD len=GetFileVersionInfoSizeW(path,&ignored);
    if(len==0||len>1048576)return v;
    std::vector<BYTE> data(len);
    if(!GetFileVersionInfoW(path,0,len,data.data()))return v;
    VS_FIXEDFILEINFO *fixed=nullptr;
    UINT size=0;
    if(!VerQueryValueW(data.data(),L"\\",reinterpret_cast<LPVOID*>(&fixed),&size)||
       !fixed||size<sizeof(VS_FIXEDFILEINFO))return v;
    v.ms=fixed->dwFileVersionMS;
    v.ls=fixed->dwFileVersionLS;
    v.valid=true;
    return v;
}
static void M3kDrawInstalledDllVersions()
{
    static ULONGLONG refresh=0;
    static M3kDllVersion sr={},nr={};
    ULONGLONG now=GetTickCount64();
    if(now>=refresh)
    {
        sr=M3kVersionOfInstalledDll(L"nvngx_dlss.dll");
        nr=M3kVersionOfInstalledDll(L"m3k\\nvngx_dlssnr.dll");
        refresh=now+5000;
    }
    ImGui::Separator();
    ImGui::TextUnformatted("Installed NVIDIA DLLs (restart after replacement)");
    if(sr.valid)
        ImGui::Text("DLAA / DLSS 4.5 | SR DLL %u.%u.%u.%u",
            HIWORD(sr.ms),LOWORD(sr.ms),HIWORD(sr.ls),LOWORD(sr.ls));
    else ImGui::TextUnformatted("DLAA / DLSS 4.5 | SR DLL unavailable");
    if(nr.valid)
    {
        // Size helps identify known variants; it is not a cryptographic validation.
        const char *variant="unknown variant";
        if(nr.bytes==276162560ull)variant="RTX 20/30/40 compat";
        else if(nr.bytes==266424944ull)variant="RTX 50 original";
        ImGui::Text("DLSS 5 | NR DLL %u.%u.%u.%u (%s)",
            HIWORD(nr.ms),LOWORD(nr.ms),HIWORD(nr.ls),LOWORD(nr.ls),variant);
    }
    else ImGui::TextUnformatted("DLSS 5 | NR DLL unavailable");
}
'@
Once $newName ($helper+[Environment]::NewLine+$newName) 'C++ version reader'
$uiEnd=@'
            if(ImGui::Combo("Technology##M3KScalingTechnology",&technology,technologyItems))
                M3kRequestScalingTechnologyLive(technology==1?2u:0u);
        }
'@
Once $uiEnd ($uiEnd+[Environment]::NewLine+'        M3kDrawInstalledDllVersions();'+[Environment]::NewLine) 'panel insertion'
foreach($marker in @('DLSS 4.5 | SR DLL','DLSS 5 | NR DLL','M3kDrawInstalledDllVersions')){
    if(-not $script:feed.Contains($marker)){throw "Version marker missing: $marker"}
}
[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'ReShade add-on version labels inserted.'
