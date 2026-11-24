#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ==============================================================================
;  AUDIO
;  Mudo de microfones, apps (som e microfone) e sistema, com janela de
;  configuração. Configurações salvas em Audio.ini (mesma pasta).
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
    {id: "AppMicMudo", nome: "Selected apps: mute microphone", padrao: "^!h", fn: (*) => AlternarMudo("AppMic")},
    {id: "AppMudo",    nome: "Selected apps: mute sound",      padrao: "^!n", fn: (*) => AlternarMudo("App")}
]

; ---------- Listas de seleção da janela ----------
; ctrl = nome do controle na janela | cfg = propriedade em Cfg | ini = seção no Audio.ini
LISTAS := [
    {ctrl: "Mics",    cfg: "mics",    ini: "Mics",    todosPadrao: 1},
    {ctrl: "Apps",    cfg: "apps",    ini: "Apps",    todosPadrao: 0},
    {ctrl: "AppsMic", cfg: "appsMic", ini: "AppsMic", todosPadrao: 0}
]

TEMAS := ["system", "light", "dark"]   ; ordem igual à da lista na janela

; ---------- Início ----------
Cfg := ConfigCarregar()
Janela := ""
Abas := [], Paginas := [], PaginaAtual := 1
Escuro := false
Preenchendo := false      ; evita salvar enquanto as listas da janela são montadas

AplicarModoApp()
MontarBandeja()
RegistrarAtalhos(Cfg.atalhos)
BandejaAtualizar()
OnMessage(0x1A, AoMudarConfigSistema)   ; WM_SETTINGCHANGE: tema claro/escuro do Windows
return


; ==============================================================================
;  AÇÕES
; ==============================================================================

; Se algum item do alvo estiver ativo, muta todos; se todos estiverem mudos, desmuta todos.
AlternarMudo(tipo) {
    a := Alvo(tipo)
    if !a.vols.Length
        return Avisar(a.nome ": " "NOTHING FOUND", "Yellow")

    mudo := !TodosMudos(a)
    for v in a.vols
        ComCall(a.vt.setMute, v, "Int", mudo, "Ptr", 0)

    Avisar(a.nome ": " (mudo ? "MUTED" : "ACTIVE"), mudo ? "Red" : "Lime")
    if Cfg.bip
        SoundBeep(mudo ? 400 : 1000, 120)     ; grave = mudo, agudo = ativo
    AposMudanca()
}

AposMudanca() {
    BandejaAtualizar()
    if JanelaVisivel()
        JanelaRecarregar()
}

; Monta o alvo de uma ação: nome exibido, tipo de interface (vt) e controles de volume.
Alvo(tipo) {
    vols := []
    switch tipo {
    case "Mic":
        for d in Dispositivos(ENTRADA)
            if Cfg.todosMics || Cfg.mics.Has(d.id)
                vols.Push(Ativar(d.dev, IID_ENDPOINT))
        return {nome: "MICROPHONES", vt: VT_ENDPOINT, vols: vols}
    case "App", "AppMic":
        mic := (tipo = "AppMic")
        for s in Sessoes(mic ? ENTRADA : SAIDA)
            if (mic ? Cfg.todosAppsMic || Cfg.appsMic.Has(s.exe) : Cfg.todosApps || Cfg.apps.Has(s.exe))
                vols.Push(s.vol)
        return {nome: mic ? "APPS (MIC)" : "APPS (SOUND)", vt: VT_APP, vols: vols}
    case "Sistema":
        try vols.Push(Ativar(SaidaPadrao(), IID_ENDPOINT))
        return {nome: "SYSTEM", vt: VT_ENDPOINT, vols: vols}
    }
}

TodosMudos(a) {
    for v in a.vols
        if !LerMudo(a.vt, v)
            return false
    return true
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

; Sessões de áudio dos apps em todos os dispositivos do fluxo -> [{exe, vol}]
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
            lista.Push({exe: exe, vol: ComObjQuery(ctl2, IID_VOL_APP)})
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
    for l in LISTAS {
        c.%"todos" l.ctrl% := IniRead(ARQ_INI, l.ini, "Todos", l.todosPadrao)
        c.%l.cfg%       := Conjunto(IniRead(ARQ_INI, l.ini, "Selecionados", ""))
    }
    for a in ACOES
        c.atalhos[a.id] := IniRead(ARQ_INI, "Atalhos", a.id, a.padrao)
    return c
}

ConfigSalvar() {
    IniWrite(Cfg.bip,    ARQ_INI, "Geral", "Bip")
    IniWrite(Cfg.aviso,  ARQ_INI, "Geral", "Aviso")
    IniWrite(Cfg.tema,   ARQ_INI, "Geral", "Tema")
    for l in LISTAS {
        IniWrite(Cfg.%"todos" l.ctrl%,     ARQ_INI, l.ini, "Todos")
        IniWrite(Juntar(Cfg.%l.cfg%),   ARQ_INI, l.ini, "Selecionados")
    }
    for a in ACOES
        IniWrite(Cfg.atalhos[a.id], ARQ_INI, "Atalhos", a.id)
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
        return {bg: "202020", fg: "E8E8E8", sutil: "9A9A9A", lista: "2B2B2B",
                abaBg: "2B2B2B", abaFg: "B0B0B0", abaAtivaBg: "0078D4", abaAtivaFg: "FFFFFF"}
    return {bg: "", fg: "000000", sutil: "666666", lista: "",
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
        case "ListView":
            TemaControle(c.Hwnd, "DarkMode_Explorer")
            cabecalho := SendMessage(0x101F, 0, 0, c)                        ; LVM_GETHEADER
            TemaControle(cabecalho, "DarkMode_ItemsView")
            ClarearCabecalho(c.Hwnd, cabecalho)
        case "DDL":
            TemaControle(c.Hwnd, "DarkMode_CFD")
        case "Checkbox":
            ; sem tema visual o texto da caixa respeita a cor da fonte (senão fica preto)
            DllCall("uxtheme\SetWindowTheme", "Ptr", c.Hwnd, "Str", "", "Str", "")
        }
    }
}

; O tema escuro deixa o texto do cabeçalho da lista quase preto. A lista recebe o
; NM_CUSTOMDRAW do cabeçalho; uma subclasse troca a cor do texto antes de desenhar.
ClarearCabecalho(hwndLista, hwndCabecalho) => DllCall("comctl32\SetWindowSubclass", "Ptr", hwndLista, "Ptr", CabecalhoCallback(), "UPtr", 1, "UPtr", hwndCabecalho)

CabecalhoCallback() {
    static cb := CallbackCreate(CabecalhoSubclasse, , 6)
    return cb
}

CabecalhoSubclasse(hwnd, msg, wParam, lParam, id, cabecalho) {
    if (msg = 0x4E && NumGet(lParam, 0, "Ptr") = cabecalho
        && NumGet(lParam, 2 * A_PtrSize, "Int") = -12) {                  ; WM_NOTIFY, NM_CUSTOMDRAW
        estagio := NumGet(lParam, 3 * A_PtrSize, "UInt")
        if (estagio = 1)                                                    ; CDDS_PREPAINT
            return 0x20                                                     ; CDRF_NOTIFYITEMDRAW
        if (estagio = 0x10001) {                                            ; CDDS_ITEMPREPAINT
            DllCall("gdi32\SetTextColor", "Ptr", NumGet(lParam, 4 * A_PtrSize, "Ptr"), "UInt", 0xD0D0D0)
            return 0                                                        ; CDRF_DODEFAULT
        }
    }
    if (msg = 0x82)                                                         ; WM_NCDESTROY
        DllCall("comctl32\RemoveWindowSubclass", "Ptr", hwnd, "Ptr", CabecalhoCallback(), "UPtr", id)
    return DllCall("comctl32\DefSubclassProc", "Ptr", hwnd, "UInt", msg, "UPtr", wParam, "Ptr", lParam, "Ptr")
}

TemaControle(hwnd, nome) =>DllCall("uxtheme\SetWindowTheme", "Ptr", hwnd, "Str", nome, "Ptr", 0)


; ==============================================================================
;  JANELA
; ==============================================================================

JanelaMostrar() {
    global Janela
    if !Janela
        Janela := JanelaCriar()
    JanelaRecarregar()
    Janela.Show()
}

JanelaVisivel() => Janela && DllCall("IsWindowVisible", "Ptr", Janela.Hwnd)

; Recria a janela (troca de tema), mantendo posição e aba.
JanelaReconstruir() {
    global Janela
    if !Janela
        return
    visivel := JanelaVisivel()
    Janela.GetPos(&x, &y)
    Janela.Destroy()
    Janela := JanelaCriar()
    JanelaRecarregar()
    if visivel
        Janela.Show("x" x " y" y)
}

JanelaCriar() {
    global Abas, Paginas
    P := Paleta()
    g := Gui(, "Audio")
    g.SetFont("s10 c" P.fg, "Segoe UI")
    if (P.bg != "")
        g.BackColor := P.bg
    g.OnEvent("Escape", (*) => g.Hide())

    ; Abas desenhadas com Text (o controle Tab do Windows não tem modo escuro)
    Abas := []
    for i, nome in ["Microphone", "Mixer", "Settings"] {
        aba := g.Add("Text", (i = 1 ? "x10 y10" : "x+2 yp") " w140 h30 Center 0x200", nome)   ; 0x200 = centraliza na vertical
        aba.OnEvent("Click", MostrarPagina.Bind(i))
        Abas.Push(aba)
    }
    inicio := [Contar(g)]

    ; --- Microfone: dispositivo inteiro + microfone por app ---
    Titulo(g, "Devices — mute the whole microphone (all apps)", true)
    CriarLista(g, "Mics", "All microphones", "Microphone", 130, P)
    g.Add("Button", "xs w140", "Mute on/off").OnEvent("Click", (*) => AlternarMudo("Mic"))
    g.Add("Button", "x+10 w140", "Refresh").OnEvent("Click", (*) => JanelaRecarregar())

    Titulo(g, "Per app — microphone each app is capturing")
    CriarLista(g, "AppsMic", "All apps", "App", 130, P)
    g.Add("Button", "xs w140", "Mute on/off").OnEvent("Click", (*) => AlternarMudo("AppMic"))
    g.Add("Button", "x+10 w140", "Refresh").OnEvent("Click", (*) => JanelaRecarregar())
    inicio.Push(Contar(g))

    ; --- Mixer: sistema + som de cada app ---
    Titulo(g, "System — default output (speakers/headphones)", true)
    g.Add("Slider", "xs w490 Range0-100 ToolTip vSisVol").OnEvent("Change", (s, *) => (SoundSetVolume(s.Value), AtualizarSistema()))
    g.Add("Text", "xs w490 vSisEstado")
    g.Add("Button", "xs w140", "Mute on/off").OnEvent("Click", (*) => AlternarMudo("Sistema"))

    Titulo(g, "Per app — sound each app plays")
    CriarLista(g, "Apps", "All apps", "App", 200, P)
    g.Add("Button", "xs w140", "Mute on/off").OnEvent("Click", (*) => AlternarMudo("App"))
    g.Add("Button", "x+10 w140", "Refresh").OnEvent("Click", (*) => JanelaRecarregar())
    inicio.Push(Contar(g))

    ; --- Configurações: atalhos + opções ---
    Titulo(g, "Hotkeys", true)
    for a in ACOES {
        g.Add("Text", "xs y+" (A_Index = 1 ? 8 : 12) " w240", a.nome)
        g.Add("Hotkey", "x+10 yp-3 w200 vHK_" a.id, Cfg.atalhos[a.id])
    }

    Titulo(g, "Options")
    corLista := Escuro ? " Background" P.lista : ""
    g.Add("Text", "xs y+8 w240", "Theme:")
    g.Add("DropDownList", "x+10 yp-3 w200 vTema Choose" Posicao(TEMAS, Cfg.tema) corLista,
        ["Follow system", "Light", "Dark"])
    g.Add("Checkbox", "xs y+14 vBip Checked" Cfg.bip, "Beep on mute/unmute")
    g.Add("Checkbox", "x+20 vAviso Checked" Cfg.aviso, "On-screen notice")
    g.Add("Button", "xs y+16 w200", "Save").OnEvent("Click", SalvarOpcoes)
    g.Add("Text", "xs y+10 w490 c" P.sutil, "To clear a hotkey: click the field and press Backspace.`nHotkeys are paused while this window is focused.")
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

; Título em negrito de uma seção. primeiro = true no topo da página.
Titulo(g, texto, primeiro := false) {
    g.SetFont("bold")
    g.Add("Text", (primeiro ? "x20 y55 Section" : "xs y+18 Section") " w490", texto)
    g.SetFont("norm")
}

; Caixa "Todos" + lista com caixas de marcar.
; A 3ª coluna (oculta) guarda a chave: id do microfone ou nome do .exe.
CriarLista(g, nome, textoTodos, titulo, altura, P) {
    g.Add("Checkbox", "xs vTodos" nome " Checked" Cfg.%"todos" nome%, textoTodos).OnEvent("Click", SalvarSelecao)
    cor := Escuro ? " Background" P.lista " c" P.fg : ""
    lv := g.Add("ListView", "xs w490 h" altura " Checked -Multi v" nome cor, [titulo, "State", "key"])
    lv.ModifyCol(1, 330), lv.ModifyCol(2, 135), lv.ModifyCol(3, 0)
    lv.OnEvent("ItemCheck", SalvarSelecao)
}

; Com "Todos" marcado a lista não importa: texto em cinza em vez de desabilitar
; (lista desabilitada ignora a cor de fundo e fica clara no tema escuro).
ListaApagada(lv, apagada) {
    P := Paleta()
    lv.Opt("c" (apagada ? P.sutil : P.fg))
    lv.Redraw()
}

JanelaRecarregar() {
    global Preenchendo := true
    try {
        PreencherLista(Janela["Mics"],    ItensMics(),        Cfg.mics,    "(microphone disconnected)")
        PreencherLista(Janela["Apps"],    ItensApps(SAIDA),   Cfg.apps,    "")
        PreencherLista(Janela["AppsMic"], ItensApps(ENTRADA), Cfg.appsMic, "")
    } finally {
        Preenchendo := false
    }
    for l in LISTAS
        ListaApagada(Janela[l.ctrl], Cfg.%"todos" l.ctrl%)
    AtualizarSistema()
}

; Itens selecionados que não estão presentes agora também aparecem, para poder desmarcar.
PreencherLista(lv, itens, selecionados, nomeAusente) {
    lv.Delete()
    presentes := Map()
    for it in itens {
        presentes[it.chave] := true
        lv.Add(selecionados.Has(it.chave) ? "Check" : "", it.nome, it.estado, it.chave)
    }
    for chave in selecionados
        if !presentes.Has(chave)
            lv.Add("Check", nomeAusente || chave, "not found", chave)
}

ItensMics() {
    itens := []
    for d in Dispositivos(ENTRADA) {
        mudo := LerMudo(VT_ENDPOINT, Ativar(d.dev, IID_ENDPOINT))
        itens.Push({chave: d.id, nome: d.nome, estado: mudo ? "Muted" : "Active"})
    }
    return itens
}

ItensApps(fluxo) {
    porExe := Map()   ; um app pode ter várias sessões: mostra uma linha por .exe
    for s in Sessoes(fluxo) {
        estado := (LerMudo(VT_APP, s.vol) ? "Muted" : "Active") " · " Round(LerVolume(VT_APP, s.vol) * 100) "%"
        porExe[s.exe] := {chave: s.exe, nome: s.exe, estado: estado}
    }
    itens := []
    for , it in porExe
        itens.Push(it)
    return itens
}

AtualizarSistema() {
    try {
        Janela["SisVol"].Value := Round(SoundGetVolume())
        Janela["SisEstado"].Value := "State: " (SoundGetMute() ? "Muted" : "Active")
    } catch {
        Janela["SisEstado"].Value := "No audio output found"
    }
}

SalvarSelecao(*) {
    if Preenchendo
        return
    for l in LISTAS {
        Cfg.%"todos" l.ctrl% := Janela["Todos" l.ctrl].Value
        Cfg.%l.cfg%       := Marcados(Janela[l.ctrl])
        ListaApagada(Janela[l.ctrl], Cfg.%"todos" l.ctrl%)
    }
    ConfigSalvar()
    BandejaAtualizar()
}

Marcados(lv) {
    s := Map(), linha := 0
    while linha := lv.GetNext(linha, "C")
        s[lv.GetText(linha, 3)] := true
    return s
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

    if mudouTema {
        AplicarModoApp()
        SetTimer(JanelaReconstruir, -1)          ; fora deste evento, pois a janela é destruída
    }
    Avisar("SETTINGS SAVED", "Lime")
}


; ==============================================================================
;  BANDEJA E AVISO NA TELA
; ==============================================================================

MontarBandeja() {
    m := A_TrayMenu
    m.Delete()
    m.Add("Open Audio", (*) => JanelaMostrar())
    m.Add("Microphones: mute on/off", (*) => AlternarMudo("Mic"))
    m.Add()
    m.Add("Reload", (*) => Reload())
    m.Add("Exit", (*) => ExitApp())
    m.Default := "Open Audio"        ; duplo clique no ícone abre a janela
}

; O ícone mostra o estado dos microfones selecionados: X = mudo, visto = ativo
BandejaAtualizar() {
    a := Alvo("Mic")
    if !a.vols.Length
        icone := 132, estado := "none selected"
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
