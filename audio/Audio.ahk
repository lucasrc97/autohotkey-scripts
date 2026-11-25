#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ==============================================================================
;  AUDIO
;  Mudo e volume por app (som) e mudo do microfone, com atalhos e uma
;  janela de mixer. Configurações salvas em
;  Audio.ini (mesma pasta).
;
;  O mudo do microfone é feito no próprio dispositivo (IAudioEndpointVolume),
;  igual ao botão "Mudo" do Windows: o dispositivo continua ativo, então o
;  Discord não perde o microfone depois de desmutar.
; ==============================================================================

; ---------- Constantes da API Core Audio do Windows ----------
SAIDA := 0, ENTRADA := 1   ; fluxo de áudio: caixas/fones = saída, microfones = entrada

; Posição de cada método na vtable das duas interfaces de volume usadas
VT_ENDPOINT := {getVol: 9, setVol: 7, getMute: 15, setMute: 14}   ; IAudioEndpointVolume (dispositivo)
VT_APP      := {getVol: 4, setVol: 3, getMute: 6,  setMute: 5}    ; ISimpleAudioVolume (app)

IID_ENDPOINT  := Guid("{5CDF2C82-841E-4546-9722-0CF74078229A}")   ; IAudioEndpointVolume
IID_SESSOES   := Guid("{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}")   ; IAudioSessionManager2
IID_CONTROLE2 := "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}"          ; IAudioSessionControl2
IID_VOL_APP   := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"          ; ISimpleAudioVolume

ARQ_INI := A_ScriptDir "\Audio.ini"

; ---------- Funções que podem ter atalho (esta ordem é a ordem na janela) ----------
ACOES := [
    {id: "Abrir",      nome: "Open window",                    padrao: "^!g", fn: (*) => JanelaMostrar()},
    {id: "MicMudo",    nome: "Mute microphone",                padrao: "^!h", fn: (*) => AlternarMudo("Mic"), antigo: "AppMicMudo"},
    {id: "AppMudo",    nome: "Selected apps: mute sound",      padrao: "^!n", fn: (*) => AlternarMudo("App")}
]

; ---------- Apps que cada atalho controla ----------
; cfg = conjunto em Cfg | todos = "atalho vale para todos os apps" | ini = seção no Audio.ini
LISTAS := Map(
    "out", {cfg: "apps", todos: "todosApps", ini: "Apps", atalho: "AppMudo"}
)

TEMAS := ["system", "light", "dark"]   ; ordem igual à da lista na janela

; Ícones da fonte Segoe MDL2 Assets (vem com o Windows 10/11)
ICO_SOM := Chr(0xE767), ICO_MUDO := Chr(0xE74F), ICO_MIC := Chr(0xE720), ICO_MIC_MUDO := Chr(0xF781), ICO_CAIXA := Chr(0xE7F5)

; ---------- Início ----------
Cfg := ConfigCarregar()
Janela := ""
Abas := [], Paginas := [], PaginaAtual := 1
Linhas := Map()            ; "tipo|chave" -> controles de uma linha da janela
Assinatura := ""           ; quais linhas a janela tem; se mudar, a janela é refeita
Escuro := false

AplicarModoApp()
MontarBandeja()
RegistrarAtalhos(Cfg.atalhos)
BandejaAtualizar()
OnMessage(0x1A, AoMudarConfigSistema)   ; WM_SETTINGCHANGE: tema claro/escuro do Windows
return


; ==============================================================================
;  AÇÕES
; ==============================================================================

; Atalhos e bandeja. Se algum item estiver ativo, muta todos; se todos estiverem mudos, desmuta.
AlternarMudo(tipo) {
    a := Alvo(tipo)
    if !a.vols.Length
        return Avisar(a.nome ": NOTHING FOUND", "Yellow")

    mudo := !TodosMudos(a)
    for v in a.vols
        ComCall(a.vt.setMute, v, "Int", mudo, "Ptr", 0)

    Avisar(a.nome ": " (mudo ? "MUTED" : "ACTIVE"), mudo ? "Red" : "Lime")
    if Cfg.bip
        SoundBeep(mudo ? 400 : 1000, 120)     ; grave = mudo, agudo = ativo
    AposMudanca()
}

; Monta o alvo de uma ação: nome exibido, tipo de interface (vt) e controles de volume.
Alvo(tipo) {
    vols := []
    switch tipo {
    case "Mic":
        for d in Dispositivos(ENTRADA)
            vols.Push(Ativar(d.dev, IID_ENDPOINT))
        return {nome: "MICROPHONES", vt: VT_ENDPOINT, vols: vols}
    case "App":
        l := LISTAS["out"]
        for s in Sessoes(SAIDA)
            if Cfg.%l.todos% || Cfg.%l.cfg%.Has(s.exe)
                vols.Push(s.vol)
        return {nome: "APPS (SOUND)", vt: VT_APP, vols: vols}
    }
}

TodosMudos(a) {
    for v in a.vols
        if !LerMudo(a.vt, v)
            return false
    return true
}

AposMudanca() {
    BandejaAtualizar()
    if JanelaVisivel()
        AtualizarJanela()
}

; Controles de volume de uma linha da janela.
;   sis = saída padrão | mic = microfone (id) | out = som do app (exe) | in = microfone do app (exe)
VolsDaLinha(tipo, chave) {
    vols := []
    switch tipo {
    case "sis":
        try vols.Push(Ativar(SaidaPadrao(), IID_ENDPOINT))
    case "mic":
        for d in Dispositivos(ENTRADA)
            if (d.id = chave)
                vols.Push(Ativar(d.dev, IID_ENDPOINT))
    case "out":
        for s in Sessoes(SAIDA)
            if (s.exe = chave)
                vols.Push(s.vol)
    }
    return vols
}

VtDe(tipo) => (tipo = "sis" || tipo = "mic") ? VT_ENDPOINT : VT_APP

LinhaMudo(tipo, chave, *) {
    a := {vt: VtDe(tipo), vols: VolsDaLinha(tipo, chave)}
    if !a.vols.Length
        return
    mudo := !TodosMudos(a)
    for v in a.vols
        ComCall(a.vt.setMute, v, "Int", mudo, "Ptr", 0)
    AposMudanca()
}

LinhaVolume(tipo, chave, slider, *) {
    vt := VtDe(tipo)
    for v in VolsDaLinha(tipo, chave)
        ComCall(vt.setVol, v, "Float", slider.Value / 100, "Ptr", 0)
    l := Linhas[tipo "|" chave]
    l.item.vol := slider.Value
    if !l.item.mudo
        l.estado.Value := slider.Value "%"
}


; ==============================================================================
;  CORE AUDIO (API do Windows), independe do idioma e do nome do dispositivo
; ==============================================================================

Enumerador() {   ; IMMDeviceEnumerator
    static e := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", "{A95664D2-9614-4F35-A746-DE8DB63617E6}")
    return e
}

; Dispositivos ativos do fluxo (SAIDA ou ENTRADA) -> [{id, nome, dev}]
Dispositivos(fluxo) {
    pCol := 0, n := 0
    ComCall(3, Enumerador(), "Int", fluxo, "UInt", 1, "Ptr*", &pCol)   ; EnumAudioEndpoints(fluxo, só ativos)
    col := ComValue(13, pCol)
    ComCall(3, col, "UInt*", &n)                                        ; GetCount
    lista := []
    Loop n {
        pDev := 0
        ComCall(4, col, "UInt", A_Index - 1, "Ptr*", &pDev)            ; Item
        dev := ComValue(13, pDev)
        lista.Push({id: DispositivoId(dev), nome: DispositivoNome(dev), dev: dev})
    }
    return lista
}

SaidaPadrao() {
    p := 0
    ComCall(4, Enumerador(), "Int", SAIDA, "Int", 0, "Ptr*", &p)   ; GetDefaultAudioEndpoint(saída, console)
    return ComValue(13, p)
}

Ativar(dev, iid) {
    p := 0
    ComCall(3, dev, "Ptr", iid, "UInt", 23, "Ptr", 0, "Ptr*", &p)   ; IMMDevice::Activate(CLSCTX_ALL)
    return ComValue(13, p)
}

DispositivoId(dev) {
    p := 0
    ComCall(5, dev, "Ptr*", &p)                    ; GetId
    id := StrGet(p)
    DllCall("ole32\CoTaskMemFree", "Ptr", p)
    return id
}

DispositivoNome(dev) {
    static chave := ChaveNomeAmigavel()
    pLoja := 0
    ComCall(4, dev, "UInt", 0, "Ptr*", &pLoja)     ; OpenPropertyStore(leitura)
    loja := ComValue(13, pLoja)
    pv := Buffer(24, 0)                            ; PROPVARIANT
    ComCall(5, loja, "Ptr", chave, "Ptr", pv)      ; GetValue
    nome := NumGet(pv, 0, "UShort") = 31 ? StrGet(NumGet(pv, 8, "Ptr")) : "(no name)"   ; 31 = VT_LPWSTR
    DllCall("ole32\PropVariantClear", "Ptr", pv)
    return nome
}

ChaveNomeAmigavel() {   ; PKEY_Device_FriendlyName
    k := Guid("{A45C254E-DF1C-4EFD-8020-67D146A850E0}", 20)
    NumPut("UInt", 14, k, 16)
    return k
}

; Sessões de áudio dos apps em todos os dispositivos do fluxo -> [{exe, pid, vol}]
;   SAIDA   = som que o app toca (caixas/fones)
;   ENTRADA = microfone que o app está captando
Sessoes(fluxo) {
    lista := []
    for d in Dispositivos(fluxo) {
        gerente := Ativar(d.dev, IID_SESSOES)
        pEnum := 0, n := 0
        ComCall(5, gerente, "Ptr*", &pEnum)                         ; GetSessionEnumerator
        enum := ComValue(13, pEnum)
        ComCall(3, enum, "Int*", &n)                                ; GetCount
        Loop n {
            pCtl := 0, estado := 0, pid := 0
            ComCall(4, enum, "Int", A_Index - 1, "Ptr*", &pCtl)    ; GetSession
            ctl := ComValue(13, pCtl)
            ComCall(3, ctl, "Int*", &estado)                        ; GetState
            if (estado = 2)
                continue                                            ; sessão expirada (app já fechou)
            ctl2 := ComObjQuery(ctl, IID_CONTROLE2)
            ComCall(14, ctl2, "UInt*", &pid)                        ; GetProcessId
            if !pid
                continue                                            ; sons do sistema
            try exe := StrLower(ProcessGetName(pid))
            catch
                continue                                            ; processo já encerrado
            lista.Push({exe: exe, pid: pid, vol: ComObjQuery(ctl2, IID_VOL_APP)})
        }
    }
    return lista
}

LerMudo(vt, vol) {
    m := 0
    ComCall(vt.getMute, vol, "Int*", &m)
    return m
}

LerVolume(vt, vol) {
    x := 0.0
    ComCall(vt.getVol, vol, "Float*", &x)
    return x
}

Guid(texto, tamanho := 16) {
    b := Buffer(tamanho, 0)
    DllCall("ole32\CLSIDFromString", "WStr", texto, "Ptr", b, "HRESULT")
    return b
}


; ==============================================================================
;  ESTADO ATUAL (o que a janela mostra)
; ==============================================================================

; -> {sis, mics[], out[], inp[]}; cada item: {tipo, chave, nome, icone, mudo, vol, presente}
LerEstado() {
    e := {sis: "", mics: [], out: [], inp: []}
    try {
        dev := SaidaPadrao(), v := Ativar(dev, IID_ENDPOINT)
        e.sis := {tipo: "sis", chave: "", nome: DispositivoNome(dev), icone: "", presente: true,
                  mudo: LerMudo(VT_ENDPOINT, v), vol: Round(LerVolume(VT_ENDPOINT, v) * 100)}
    }
    for d in Dispositivos(ENTRADA) {
        v := Ativar(d.dev, IID_ENDPOINT)
        e.mics.Push({tipo: "mic", chave: d.id, nome: d.nome, icone: "", presente: true,
                     mudo: LerMudo(VT_ENDPOINT, v), vol: 0})
    }
    e.out := ItensApps("out", SAIDA)
    e.inp := AppsNoMic()
    return e
}

; Apps captando o microfone agora. Só informação: o Windows não muta o microfone
; de um app só (mutar a sessão de um app muta o dispositivo inteiro).
AppsNoMic() {
    porExe := Map()
    for s in Sessoes(ENTRADA)
        if !porExe.Has(s.exe) {
            info := InfoApp(s.exe, s.pid)
            porExe[s.exe] := {tipo: "uso", chave: s.exe, nome: info.nome, icone: info.caminho,
                              presente: true, mudo: false, vol: 0}
        }
    lista := []
    for , it in porExe
        lista.Push(it)
    return lista
}

; Uma linha por .exe (um app pode ter várias sessões). Apps marcados que não estão
; usando áudio agora também aparecem, como "not running", para poder desmarcar.
ItensApps(tipo, fluxo) {
    porExe := Map()
    for s in Sessoes(fluxo) {
        mudo := LerMudo(VT_APP, s.vol), vol := Round(LerVolume(VT_APP, s.vol) * 100)
        if porExe.Has(s.exe) {
            it := porExe[s.exe]
            it.mudo := it.mudo && mudo                  ; mudo só se todas as sessões estiverem
            it.vol := Max(it.vol, vol)
        } else {
            info := InfoApp(s.exe, s.pid)
            porExe[s.exe] := {tipo: tipo, chave: s.exe, nome: info.nome, icone: info.caminho,
                              presente: true, mudo: mudo, vol: vol}
        }
    }
    lista := []
    for , it in porExe
        lista.Push(it)
    for exe in Cfg.%LISTAS[tipo].cfg%
        if !porExe.Has(exe) {
            info := InfoApp(exe, 0)
            lista.Push({tipo: tipo, chave: exe, nome: info.nome, icone: info.caminho,
                        presente: false, mudo: false, vol: 0})
        }
    return lista
}

TodosItens(e) {
    lista := e.sis ? [e.sis] : []
    for grupo in [e.mics, e.out, e.inp]
        for it in grupo
            lista.Push(it)
    return lista
}

AssinaturaDe(e) {
    s := ""
    for it in TodosItens(e)
        s .= "|" it.tipo ":" it.chave ":" it.presente
    return s
}

; Nome amigável ("Google Chrome" em vez de chrome.exe) e caminho do .exe para o ícone.
; Fica guardado no Audio.ini para apps marcados que não estão abertos.
InfoApp(exe, pid) {
    static cache := Map()
    if cache.Has(exe)
        return cache[exe]
    salvo := IniRead(ARQ_INI, "Info", exe, "")
    partes := StrSplit(salvo, "|")
    nome := partes.Length ? partes[1] : "", caminho := partes.Length > 1 ? partes[2] : ""
    if pid {
        try caminho := ProcessGetPath(pid)
        if (caminho != "")
            nome := DescricaoArquivo(caminho) || nome
    }
    if (nome = "")
        nome := NomeSimples(exe)
    info := {nome: nome, caminho: (caminho != "" && FileExist(caminho)) ? caminho : ""}
    if pid {
        cache[exe] := info
        if (nome "|" caminho != salvo)
            IniWrite(nome "|" caminho, ARQ_INI, "Info", exe)
    }
    return info
}

NomeSimples(exe) {   ; "chrome.exe" -> "Chrome"
    n := RegExReplace(exe, "i)\.exe$")
    return StrUpper(SubStr(n, 1, 1)) SubStr(n, 2)
}

DescricaoArquivo(caminho) {   ; FileDescription do .exe, "" se não tiver
    tam := DllCall("version\GetFileVersionInfoSizeW", "Str", caminho, "Ptr", 0, "UInt")
    if !tam
        return ""
    buf := Buffer(tam)
    if !DllCall("version\GetFileVersionInfoW", "Str", caminho, "UInt", 0, "UInt", tam, "Ptr", buf)
        return ""
    p := 0, n := 0
    if !DllCall("version\VerQueryValueW", "Ptr", buf, "Str", "\VarFileInfo\Translation", "Ptr*", &p, "UInt*", &n) || n < 4
        return ""
    idioma := Format("{:04X}{:04X}", NumGet(p, 0, "UShort"), NumGet(p, 2, "UShort"))
    if DllCall("version\VerQueryValueW", "Ptr", buf, "Str", "\StringFileInfo\" idioma "\FileDescription", "Ptr*", &p, "UInt*", &n) && n > 1
        return Trim(StrGet(p))
    return ""
}


; ==============================================================================
;  ATALHOS
; ==============================================================================

; Os atalhos ficam desligados enquanto a janela do Audio está em foco,
; para que você possa gravar um atalho novo sem disparar o antigo.
ForaDaJanela(*) => !(Janela && WinActive("ahk_id " Janela.Hwnd))

; Liga os atalhos informados (desligando os anteriores). Retorna true se todos funcionaram.
RegistrarAtalhos(atalhos) {
    static ativos := []
    HotIf(ForaDaJanela)
    for tecla in ativos
        try Hotkey(tecla, "Off")
    ativos := [], erros := ""
    for a in ACOES {
        tecla := atalhos[a.id]
        if (tecla = "")
            continue
        try {
            Hotkey(tecla, a.fn, "On")
            ativos.Push(tecla)
        } catch as e {
            erros .= "`n• " a.nome " (" tecla "): " e.Message
        }
    }
    HotIf()
    if erros
        MsgBox("Could not register:" erros, "Audio", "Icon!")
    return erros = ""
}

; "^!n" -> "Ctrl+Alt+N"
AtalhoTexto(tecla) {
    static mods := Map("^", "Ctrl", "!", "Alt", "+", "Shift", "#", "Win")
    texto := ""
    while (StrLen(tecla) > 1 && mods.Has(SubStr(tecla, 1, 1))) {
        texto .= mods[SubStr(tecla, 1, 1)] "+"
        tecla := SubStr(tecla, 2)
    }
    return texto (StrLen(tecla) = 1 ? StrUpper(tecla) : tecla)
}


; ==============================================================================
;  CONFIGURAÇÃO (Audio.ini)
; ==============================================================================

ConfigCarregar() {
    c := {
        bip:     IniRead(ARQ_INI, "Geral", "Bip", 1),
        aviso:   IniRead(ARQ_INI, "Geral", "Aviso", 1),
        tema:    IniRead(ARQ_INI, "Geral", "Tema", "system"),
        atalhos: Map()
    }
    if !Posicao(TEMAS, c.tema)
        c.tema := "system"
    for , l in LISTAS {
        c.%l.todos% := IniRead(ARQ_INI, l.ini, "Todos", 0)
        c.%l.cfg%   := Conjunto(IniRead(ARQ_INI, l.ini, "Selecionados", ""))
    }
    for a in ACOES
        c.atalhos[a.id] := IniRead(ARQ_INI, "Atalhos", a.id,
            a.HasOwnProp("antigo") ? IniRead(ARQ_INI, "Atalhos", a.antigo, a.padrao) : a.padrao)
    return c
}

ConfigSalvar() {
    IniWrite(Cfg.bip,   ARQ_INI, "Geral", "Bip")
    IniWrite(Cfg.aviso, ARQ_INI, "Geral", "Aviso")
    IniWrite(Cfg.tema,  ARQ_INI, "Geral", "Tema")
    for , l in LISTAS {
        IniWrite(Cfg.%l.todos%,       ARQ_INI, l.ini, "Todos")
        IniWrite(Juntar(Cfg.%l.cfg%), ARQ_INI, l.ini, "Selecionados")
    }
    for a in ACOES
        IniWrite(Cfg.atalhos[a.id], ARQ_INI, "Atalhos", a.id)
    ; limpa entradas de versões antigas
    try IniDelete(ARQ_INI, "Atalhos", "AppMicMudo")
    try IniDelete(ARQ_INI, "AppsMic")
    try IniDelete(ARQ_INI, "Mics")
}

Conjunto(texto) {   ; "a|b|c" -> Map(a, b, c)
    s := Map()
    for item in StrSplit(texto, "|")
        if (item != "")
            s[item] := true
    return s
}

Juntar(conjunto) {  ; Map(a, b, c) -> "a|b|c"
    texto := ""
    for item in conjunto
        texto .= (texto = "" ? "" : "|") item
    return texto
}

Posicao(lista, valor) {   ; índice do valor no array, 0 se não existir
    for i, v in lista
        if (v = valor)
            return i
    return 0
}


; ==============================================================================
;  TEMA (claro / escuro / seguir o sistema)
; ==============================================================================

TemaEscuro() {
    switch Cfg.tema {
    case "dark":  return true
    case "light": return false
    }
    try return !RegRead("HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize", "AppsUseLightTheme")
    return false
}

Paleta() {
    if Escuro
        return {bg: "202020", fg: "E8E8E8", sutil: "9A9A9A", mudo: "FF6B6B", ativo: "4CC38A",
                abaBg: "2B2B2B", abaFg: "B0B0B0", abaAtivaBg: "0078D4", abaAtivaFg: "FFFFFF"}
    return {bg: "", fg: "000000", sutil: "6E6E6E", mudo: "C42B1C", ativo: "107C10",
            abaBg: "E1E1E1", abaFg: "333333", abaAtivaBg: "0078D4", abaAtivaFg: "FFFFFF"}
}

; Modo do app inteiro: deixa o menu da bandeja escuro/claro (APIs não documentadas do uxtheme).
AplicarModoApp() {
    global Escuro := TemaEscuro()
    static ux := DllCall("LoadLibrary", "Str", "uxtheme", "Ptr")
    try {
        DllCall(DllCall("GetProcAddress", "Ptr", ux, "Ptr", 135, "Ptr"), "Int", Escuro ? 2 : 3)   ; SetPreferredAppMode
        DllCall(DllCall("GetProcAddress", "Ptr", ux, "Ptr", 136, "Ptr"))                           ; FlushMenuThemes
    }
}

; O Windows avisa quando o tema muda; se estiver seguindo o sistema, refaz a janela.
AoMudarConfigSistema(wParam, lParam, *) {
    if (Cfg.tema = "system" && lParam && StrGet(lParam) = "ImmersiveColorSet")
        SetTimer(TemaDoSistemaMudou, -500)
}

TemaDoSistemaMudou() {
    if (TemaEscuro() = Escuro)
        return
    AplicarModoApp()
    JanelaReconstruir()
}

; Barra de título e controles nativos no modo escuro.
EscurecerJanela(g) {
    v := Buffer(4), NumPut("Int", 1, v)
    if DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", 20, "Ptr", v, "Int", 4)       ; Win10 20H1+ / Win11
        DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", g.Hwnd, "Int", 19, "Ptr", v, "Int", 4)      ; Win10 antigo
    for , c in g {
        switch c.Type {
        case "Button":
            TemaControle(c.Hwnd, "DarkMode_Explorer")
        case "DDL":
            TemaControle(c.Hwnd, "DarkMode_CFD")
        case "Checkbox":
            if (c.Text = "")
                TemaControle(c.Hwnd, "DarkMode_Explorer")
            else   ; sem tema visual o texto da caixa respeita a cor da fonte (senão fica preto)
                DllCall("uxtheme\SetWindowTheme", "Ptr", c.Hwnd, "Str", "", "Str", "")
        }
    }
}

TemaControle(hwnd, nome) => DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", nome, "Ptr", 0)


; ==============================================================================
;  JANELA
; ==============================================================================

JanelaMostrar() {
    global Janela
    if !Janela
        Janela := JanelaCriar(LerEstado())
    Janela.Show()
    AtualizarJanela()
    SetTimer(AtualizarJanela, 1500)     ; mantém volumes e estados em dia enquanto aberta
}

JanelaVisivel() => Janela && DllCall("IsWindowVisible", "Ptr", Janela.Hwnd)

; Atualiza os valores da janela. Se apareceu ou sumiu um app/dispositivo, refaz a janela.
AtualizarJanela() {
    if !JanelaVisivel()
        return SetTimer(AtualizarJanela, 0)
    e := LerEstado()
    if (AssinaturaDe(e) != Assinatura)
        return SetTimer(JanelaReconstruir, -1)
    for it in TodosItens(e)
        LinhaAtualizar(Linhas[it.tipo "|" it.chave], it)
}

; Recria a janela (linhas novas, tema ou atalhos), mantendo posição e aba.
JanelaReconstruir() {
    global Janela
    if !Janela
        return
    visivel := JanelaVisivel(), ativa := WinActive("ahk_id " Janela.Hwnd)
    Janela.GetPos(&x, &y)
    velha := Janela
    Janela := JanelaCriar(LerEstado())
    if visivel
        Janela.Show("x" x " y" y (ativa ? "" : " NA"))
    velha.Destroy()
}

; Geometria das linhas (largura do conteúdo: 428, margem: 16)
;   [caixa] [mudo] [ícone] Nome ............ [===== volume =====]  50%
JanelaCriar(e) {
    global Abas, Paginas, Linhas := Map(), Assinatura := AssinaturaDe(e)
    P := Paleta()
    g := Gui(, "Audio")
    g.SetFont("s10 c" P.fg, "Segoe UI")
    if (P.bg != "")
        g.BackColor := P.bg
    g.OnEvent("Escape", (*) => g.Hide())

    ; Abas desenhadas com Text (o controle Tab do Windows não tem modo escuro)
    Abas := []
    for i, nome in ["Sound", "Microphone", "Settings"] {
        aba := g.Add("Text", (i = 1 ? "x16 y12" : "x+2 yp") " w140 h30 Center 0x200", nome)   ; 0x200 = centraliza na vertical
        aba.OnEvent("Click", MostrarPagina.Bind(i))
        Abas.Push(aba)
    }
    inicio := [Contar(g)]

    ; --- Sound: saída padrão + som de cada app ---
    y := 58
    Secao(g, "Output device", y), y += 28
    if e.sis
        LinhaCriar(g, e.sis, y), y += 36
    else
        Vazio(g, "No audio output found.", y), y += 30
    y += 10
    Secao(g, "Apps", y)
    EscolhaAtalho(g, "out", y - 3), y += 30
    if !e.out.Length
        Vazio(g, "No app is playing sound right now.", y), y += 30
    for it in e.out
        LinhaCriar(g, it, y), y += 34
    inicio.Push(Contar(g))

    ; --- Microphone: mudo dos dispositivos + apps usando o microfone (só informação) ---
    y := 58
    Secao(g, "Microphones", y)
    tecla := AtalhoTexto(Cfg.atalhos["MicMudo"])
    if (tecla != "")
        g.Add("Text", "x170 y" y " w274 Right c" P.sutil, tecla " mutes all microphones")
    y += 28
    if !e.mics.Length
        Vazio(g, "No microphone found.", y), y += 30
    for it in e.mics
        LinhaCriar(g, it, y), y += 34
    y += 10
    Secao(g, "Apps using the microphone", y, 428), y += 28
    if !e.inp.Length
        Vazio(g, "No app is using the microphone right now.", y), y += 30
    for it in e.inp
        LinhaCriar(g, it, y), y += 34
    g.Add("Text", "x16 y" (y + 8) " w428 c" P.sutil,
        "Windows can only mute the whole microphone, not a single app.")
    inicio.Push(Contar(g))

    ; --- Settings: atalhos + opções ---
    y := 58
    Secao(g, "Hotkeys", y), y += 28
    for a in ACOES {
        g.Add("Text", "x16 y" (y + 3) " w220", a.nome)
        g.Add("Hotkey", "x246 y" y " w198 vHK_" a.id, Cfg.atalhos[a.id])
        y += 32
    }
    y += 10
    Secao(g, "Options", y), y += 28
    g.Add("Text", "x16 y" (y + 3) " w220", "Theme:")
    g.Add("DropDownList", "x246 y" y " w198 vTema Choose" Posicao(TEMAS, Cfg.tema), ["Follow system", "Light", "Dark"])
    y += 36
    g.Add("Checkbox", "x16 y" y " vBip Checked" Cfg.bip, "Beep on mute/unmute")
    g.Add("Checkbox", "x246 y" y " vAviso Checked" Cfg.aviso, "On-screen notice")
    y += 34
    g.Add("Button", "x16 y" y " w140 h30", "Save").OnEvent("Click", SalvarOpcoes)
    g.Add("Text", "x16 y" (y + 44) " w428 c" P.sutil,
        "To clear a hotkey: click the field and press Backspace.`nHotkeys are paused while this window is focused.")
    inicio.Push(Contar(g))

    ; Separa os controles de cada página pela ordem em que foram criados
    Paginas := [[], [], []]
    n := 0
    for , c in g {
        n++
        Loop 3
            if (n > inicio[A_Index] && n <= inicio[A_Index + 1])
                Paginas[A_Index].Push(c)
    }

    if Escuro
        EscurecerJanela(g)
    g.Show("Hide")                 ; calcula o tamanho com todas as páginas visíveis
    MostrarPagina(PaginaAtual)
    return g
}

Secao(g, texto, y, largura := 220) {
    g.SetFont("bold")
    g.Add("Text", "x16 y" y " w" largura, texto)
    g.SetFont("norm")
}

Vazio(g, texto, y) => g.Add("Text", "x16 y" y " w428 c" Paleta().sutil, texto)

; "Ctrl+Alt+N mutes: [Checked apps | All apps]" à direita do título da seção.
EscolhaAtalho(g, tipo, y) {
    l := LISTAS[tipo]
    tecla := AtalhoTexto(Cfg.atalhos[l.atalho])
    g.Add("Text", "x170 y" (y + 3) " w140 Right c" Paleta().sutil, (tecla != "" ? tecla : "Hotkey") " mutes:")
    dd := g.Add("DropDownList", "x316 y" y " w128 Choose" (Cfg.%l.todos% ? 2 : 1), ["Checked apps", "All apps"])
    dd.OnEvent("Change", EscopoMudou.Bind(tipo))
}

; Uma linha: item = {tipo, chave, nome, icone, mudo, vol, presente}
LinhaCriar(g, it, y) {
    P := Paleta()
    l := {item: it, cor: ""}
    comVolume := (it.tipo = "sis" || it.tipo = "out")
    mic := (it.tipo = "mic" || it.tipo = "uso")

    if LISTAS.Has(it.tipo) {        ; app: caixa "entra no atalho"
        lst := LISTAS[it.tipo]
        l.chk := g.Add("Checkbox", "x16 y" (y + 5) " w18 h20 Checked" Cfg.%lst.cfg%.Has(it.chave), "")
        l.chk.Enabled := !Cfg.%lst.todos%
        l.chk.OnEvent("Click", MarcarApp.Bind(it.tipo, it.chave))
    }

    if !it.presente {
        g.Add("Text", "x110 y" y " w200 h28 0x4280 c" P.sutil, it.nome)        ; 0x4280 = centro, "...", sem &
        g.Add("Text", "x316 y" y " w128 h28 0x200 Right c" P.sutil, "not running")
        return Linhas[it.tipo "|" it.chave] := l
    }

    g.SetFont("s12", "Segoe MDL2 Assets")
    if (it.tipo != "uso") {           ; apps no microfone: sem botão de mudo
        l.btn := g.Add("Button", "x40 y" y " w36 h28", "")
        l.btn.OnEvent("Click", LinhaMudo.Bind(it.tipo, it.chave))
    }
    icone := ""
    if (it.icone != "")
        try icone := g.Add("Picture", "x84 y" (y + 4) " w20 h20 Icon1", it.icone)
    if !icone
        g.Add("Text", "x84 y" (y + 3) " w22 h24 c" P.sutil, mic ? ICO_MIC : ICO_CAIXA)
    g.SetFont("s10", "Segoe UI")

    g.Add("Text", "x112 y" y " w" (comVolume ? 150 : 260) " h28 0x4280", it.nome)
    if (it.tipo = "uso") {
        g.Add("Text", "x376 y" y " w68 h28 0x200 Right c" P.sutil, "In use")
        return Linhas[it.tipo "|" it.chave] := l
    }
    if comVolume {
        l.slider := g.Add("Slider", "x266 y" y " w128 h28 Range0-100 NoTicks Page10 ToolTip", it.vol)
        l.slider.OnEvent("Change", LinhaVolume.Bind(it.tipo, it.chave))
    }
    l.estado := g.Add("Text", "x" (comVolume ? 396 : 376) " y" y " w" (comVolume ? 48 : 68) " h28 0x200 Right", "")
    Linhas[it.tipo "|" it.chave] := l
    LinhaAtualizar(l, it)
}

LinhaAtualizar(l, it) {
    if !it.presente || !l.HasOwnProp("btn")
        return
    P := Paleta()
    l.item := it
    mic := (it.tipo = "mic")
    icone := it.mudo ? (mic ? ICO_MIC_MUDO : ICO_MUDO) : (mic ? ICO_MIC : ICO_SOM)
    if (l.btn.Text != icone)
        l.btn.Text := icone
    if l.HasOwnProp("slider") && !GetKeyState("LButton") && (l.slider.Value != it.vol)
        l.slider.Value := it.vol
    texto := it.mudo ? "Muted" : (mic ? "Live" : it.vol "%")
    cor := it.mudo ? P.mudo : (mic ? P.ativo : P.fg)
    if (l.estado.Value != texto)
        l.estado.Value := texto
    if (l.cor != cor)
        l.estado.SetFont("c" cor), l.cor := cor
}

MarcarApp(tipo, exe, caixa, *) {
    sel := Cfg.%LISTAS[tipo].cfg%
    if caixa.Value
        sel[exe] := true
    else if sel.Has(exe)
        sel.Delete(exe)
    ConfigSalvar()
    AtualizarJanela()          ; app fechado desmarcado some da lista
}

EscopoMudou(tipo, dd, *) {
    l := LISTAS[tipo]
    Cfg.%l.todos% := (dd.Value = 2)
    ConfigSalvar()
    for , linha in Linhas
        if (linha.item.tipo = tipo && linha.HasOwnProp("chk"))
            linha.chk.Enabled := !Cfg.%l.todos%
}

MostrarPagina(n, *) {
    global PaginaAtual := n
    P := Paleta()
    for i, ctrls in Paginas
        for c in ctrls
            c.Visible := (i = n)
    for i, aba in Abas {
        ativa := (i = n)
        aba.Opt("Background" (ativa ? P.abaAtivaBg : P.abaBg))
        aba.SetFont("c" (ativa ? P.abaAtivaFg : P.abaFg))
        aba.Redraw()
    }
}

Contar(g) {
    n := 0
    for , c in g
        n++
    return n
}

SalvarOpcoes(*) {
    novos := Map(), dono := Map()
    for a in ACOES {
        tecla := Janela["HK_" a.id].Value
        if (tecla != "") {
            if dono.Has(tecla)
                return MsgBox("The hotkey " tecla " is assigned to two functions:`n• " dono[tecla] "`n• " a.nome, "Audio", "Icon!")
            dono[tecla] := a.nome
        }
        novos[a.id] := tecla
    }
    if !RegistrarAtalhos(novos)
        return RegistrarAtalhos(Cfg.atalhos)      ; algo falhou: volta aos atalhos anteriores

    tema := TEMAS[Janela["Tema"].Value]
    mudouTema := (tema != Cfg.tema)

    Cfg.atalhos := novos
    Cfg.bip     := Janela["Bip"].Value
    Cfg.aviso   := Janela["Aviso"].Value
    Cfg.tema    := tema
    ConfigSalvar()

    if mudouTema
        AplicarModoApp()
    SetTimer(JanelaReconstruir, -1)              ; refaz fora deste evento (tema e nomes dos atalhos)
    Avisar("SETTINGS SAVED", "Lime")
}


; ==============================================================================
;  BANDEJA E AVISO NA TELA
; ==============================================================================

MontarBandeja() {
    m := A_TrayMenu
    m.Delete()
    m.Add("Open Audio", (*) => JanelaMostrar())
    m.Add("Mute/unmute microphones", (*) => AlternarMudo("Mic"))
    m.Add()
    m.Add("Reload", (*) => Reload())
    m.Add("Exit", (*) => ExitApp())
    m.Default := "Open Audio"        ; duplo clique no ícone abre a janela
}

; O ícone mostra o estado dos microfones: X = mudos, visto = ativos
BandejaAtualizar() {
    a := Alvo("Mic")
    if !a.vols.Length
        icone := 132, estado := "none found"
    else if TodosMudos(a)
        icone := 132, estado := "MUTED"
    else
        icone := 138, estado := "ACTIVE"
    TraySetIcon("Shell32.dll", icone)
    A_IconTip := "Audio — microphones " estado
}

Avisar(texto, cor) {
    static hud := 0, rotulo := 0, esconder := 0
    if !Cfg.aviso
        return
    if !hud {
        hud := Gui("+AlwaysOnTop -Caption +ToolWindow")
        hud.BackColor := "141414"
        hud.SetFont("s16 bold", "Segoe UI")
        rotulo := hud.Add("Text", "Center w320")
        esconder := ObjBindMethod(hud, "Hide")
    }
    rotulo.SetFont("c" cor)
    rotulo.Value := texto
    hud.Show("NoActivate")
    SetTimer(esconder, -1200)
}
