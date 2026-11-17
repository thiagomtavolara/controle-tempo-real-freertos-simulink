function HVAC_TCC_GUI
% HVAC_TCC_GUI Supervisiona a planta HVAC e os parametros do controlador.
%
% Uso: HVAC_TCC_GUI abre a interface de operacao com comunicacao serial.
% Compativel com MATLAB R2014a. Comunicacao serial a 115200 baud.
%
% Modos do firmware: 0 = malha aberta; 1 = controlador Simulink.
% Le perfil_controlador.txt na raiz para conferir o pacote instalado e obter
% nomes e limites dos parametros. Reabra a GUI depois de importar outro modelo.
% A GUI envia comandos e exibe registros; o controle periodico roda no Arduino.
%
% Permite salvar CSV/log, abrir registros, comparar ensaios e chamar as rotinas
% externas de identificacao e comparacao com a simulacao. Dados e resultados
% usam as subpastas de dados, resolvidas a partir da localizacao do projeto.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz

% Estado compartilhado pelos callbacks e pelo timer de leitura serial.


raiz=fileparts(fileparts(mfilename('fullpath')));
perfil=lerPerfil(fullfile(raiz,'perfil_controlador.txt'));
pacoteConferido=false;
janelaParametros=[];
uiPar=struct();
valoresParametros=nan(1,numel(perfil.nomes));
parametroPendente=0;
valorSolicitado=NaN;
aguardandoLista=false;
relogioParametros=[];
mensagemParametros='Conecte o Arduino para consultar os valores.';
ultimaFalha=-1;
envioSequencia=0;
serialObj    = [];
serialTimer  = [];
isConnected  = false;
dataLog      = zeros(0,7); % colunas: [timestamp, modo, setpoint, temperatura, controle, jitter_control_us, jitter_sensor_us]
h            = struct(); % TODOS os handles de UI ficam guardados aqui
contadorTimer = 0; % usado para atualizar os gráficos a cada ~3 ciclos do timer (900ms), não a cada leitura
avisouSemMedida = false; % evita inundar o console: avisa 1x por episódio em que o firmware manda temperatura 'nan'


labels = {
    'Referência:', '30', '°C', 'R';
    'Cooler:', '0', 'V', 'C';
    'Entrada MV:', '0', 'V', 'V';
    };



bgMain = [0.12 0.14 0.18]; % Grafite: fundo geral
bgPanel = [0.17 0.20 0.25]; % Paineis
bgTop = [0.09 0.11 0.15];
textCol = [0.92 0.95 0.98];
btnCol = [0.25 0.30 0.36];
axesCol = [0.29 0.33 0.39]; % Graficos um pouco mais claros
inputCol = [0.22 0.26 0.32];
acaoCol = [0.10 0.39 0.59];
azul = [0.32 0.78 1.00];
laranja = [1.00 0.65 0.24];
cinza = [0.76 0.81 0.87];
vermelho = [0.75 0.16 0.18];
fig = figure('Name','HVAC - Planta didática', 'NumberTitle','off', ...
    'MenuBar','none','ToolBar','none','Resize','on','Visible','off','Color',bgMain, ...
    'Units','pixels','Position',[50 50 1180 720], ...
    'CloseRequestFcn',@fecharJanela_Callback);
set(fig,'DefaultUicontrolFontName','Arial','DefaultUicontrolFontSize',10, ...
    'DefaultAxesFontName','Arial','DefaultAxesFontSize',10);

cab = uipanel('Parent',fig,'Units','pixels','Position',[0 654 1180 66], ...
    'BackgroundColor',bgTop,'BorderType','none');
criaTexto(cab,'HVAC | Planta didática',[20 27 510 29],18,[1 1 1],bgTop);
criaTexto(cab,'Controle de temperatura e supervisão em tempo real', ...
    [21 6 530 20],10,[0.74 0.81 0.89],bgTop);
criaTexto(cab,'Porta serial',[780 25 84 22],10,[1 1 1],bgTop);
portasDisponiveis = listarPortasSeriais();
h.popupPorta = uicontrol('Parent',cab,'Style','popupmenu', ...
    'String',portasDisponiveis,'BackgroundColor',inputCol,'ForegroundColor',textCol, ...
    'Position',[865 22 130 28]);
h.btnConectar = criaBotao(cab,'Conectar',[1010 19 148 34], ...
    @btnConectar_Callback,btnCol,textCol);

leftPanel = uipanel('Parent',fig,'Units','pixels','Position',[16 135 171 505], ...
    'BackgroundColor',bgPanel,'BorderType','none');
criaTexto(leftPanel,{'CONFIGURAÇÃO','DO ENSAIO'},[8 456 155 40],10,azul,bgPanel);
h.txtStatusRotina = criaTexto(leftPanel,'HVAC desconectado', ...
    [8 428 155 32],10,cinza,bgPanel);
criaTexto(leftPanel,'Modo de controle',[8 400 155 20],10,textCol,bgPanel);
h.popupRotina = uicontrol('Parent',leftPanel,'Style','popupmenu', ...
    'String',{'Selecione...','Malha aberta','Controlador Simulink'}, ...
    'BackgroundColor',inputCol,'ForegroundColor',textCol,'Position',[8 367 155 30],'FontSize',8, ...
    'Callback',@popupRotina_Callback);
numCampos = size(labels,1);
h.edits = zeros(1,numCampos);
h.fieldLabels = zeros(1,numCampos);
h.fieldUnits = zeros(1,numCampos);
h.editKeys = cell(1,numCampos);
for i=1:numCampos
    h.editKeys{i}=labels{i,4};
    h.fieldLabels(i)=criaTexto(leftPanel,labels{i,1},[8 320 64 18], ...
        10,textCol,bgPanel);
    h.edits(i)=uicontrol('Parent',leftPanel,'Style','edit', ...
        'String',labels{i,2},'BackgroundColor',inputCol, ...
        'ForegroundColor',textCol,'HorizontalAlignment','left', ...
        'Position',[76 315 54 29],'Callback',@(~,~) atualizarRotuloCompensador());
    h.fieldUnits(i)=criaTexto(leftPanel,labels{i,3},[134 320 32 18], ...
        9,cinza,bgPanel);
end
h.txtCompensador=criaTexto(leftPanel,'',[8 108 155 62],9,azul,bgPanel);
h.btnSimular=criaBotao(leftPanel,'Parâmetros Simulink',[8 78 155 30], ...
    @btnSimular_Callback,btnCol,textCol);
h.btnAtualizar=criaBotao(leftPanel,'Aplicar / iniciar',[8 40 155 32], ...
    @btnAtualizar_Callback,acaoCol,[1 1 1]);
h.btnParar=criaBotao(leftPanel,'PARAR PLANTA',[8 2 155 32], ...
    @btnParar_Callback,vermelho,[1 1 1]);

infoLabels={'Temperatura atual','Referência','Comando da lâmpada'};
infoInit={'-- °C','-- °C','-- V'};
h.indicadores=zeros(1,3);
coresIndicadores=[azul;cinza;laranja];
for k=1:3
    card=uipanel('Parent',fig,'Units','pixels','Position',[203+(k-1)*318 564 300 76], ...
        'BackgroundColor',bgPanel,'BorderType','none');
    criaTexto(card,infoLabels{k},[12 48 270 18],10,cinza,bgPanel);
    h.indicadores(k)=criaTexto(card,infoInit{k},[12 9 270 34],21, ...
        coresIndicadores(k,:),bgPanel);
    set(h.indicadores(k),'FontWeight','bold');
end

h.ax1=axes('Parent',fig,'Units','pixels','Position',[260 382 859 142], ...
    'Color',axesCol,'XColor',textCol,'YColor',textCol,'Box','off', ...
    'GridLineStyle',':','FontSize',10);
hold(h.ax1,'on');
h.linhaRef = line('Parent',h.ax1,'XData',0,'YData',0, ...
    'LineStyle','--','Color',[1 0 0],'LineWidth',1.8);
h.linhaTemp=line('Parent',h.ax1,'XData',0,'YData',0, ...
    'LineStyle','-','Color',azul,'LineWidth',1.8);
grid(h.ax1,'on'); xlabel(h.ax1,'Tempo (s)','Color',textCol); ylabel(h.ax1,'Temperatura (°C)','Color',textCol);
title(h.ax1,'Temperatura e referência','Color',textCol,'FontWeight','bold');
h.leg1=legend([h.linhaRef h.linhaTemp], ...
    {'Referência','Temperatura'},'Location','northeast','Orientation','horizontal');
set([h.linhaRef h.linhaTemp],'XData',[],'YData',[]);
set(h.leg1,'FontSize',8,'FontWeight','bold','Box','on','Color',bgPanel, ...
    'XColor',cinza,'YColor',cinza);
set(findall(h.leg1,'Type','text'),'Color',[1 1 1],'FontWeight','bold');
xlim(h.ax1,[0 60]); ylim(h.ax1,[20 40]);

h.ax2=axes('Parent',fig,'Units','pixels','Position',[260 210 859 104], ...
    'Color',axesCol,'XColor',textCol,'YColor',textCol,'Box','off', ...
    'GridLineStyle',':','FontSize',10);
hold(h.ax2,'on');
h.linhaU=line('Parent',h.ax2,'XData',0,'YData',0, ...
    'Color',laranja,'LineWidth',1.6);
grid(h.ax2,'on'); xlabel(h.ax2,'Tempo (s)','Color',textCol); ylabel(h.ax2,'Comando (V)','Color',textCol);
title(h.ax2,'Ação de controle','Color',textCol,'FontWeight','bold');
h.leg2=legend(h.linhaU,{'Lâmpada'},'Location','northeast');
set(h.linhaU,'XData',[],'YData',[]);
set(h.leg2,'FontSize',8,'FontWeight','bold','Box','on','Color',bgPanel, ...
    'XColor',cinza,'YColor',cinza);
set(findall(h.leg2,'Type','text'),'Color',[1 1 1],'FontWeight','bold');
xlim(h.ax2,[0 60]); ylim(h.ax2,[-0.5 12.5]);

h.btnPlotarCSV=criaBotao(fig,'Abrir ensaio/simulação',[260 130 163 30], ...
    @btnPlotarCSV_Callback,btnCol,textCol);
h.btnIdentificarAtual=criaBotao(fig,'Identificar planta',[434 130 163 30], ...
    @btnIdentificarAtual_Callback,btnCol,textCol);
h.btnAnalisarMultiplos=criaBotao(fig,'Comparar ensaios',[608 130 163 30], ...
    @btnAnalisarMultiplos_Callback,btnCol,textCol);
h.btnCompararSimulacao=criaBotao(fig,'Simulação x planta',[782 130 163 30], ...
    @btnCompararSimulacao_Callback,acaoCol,textCol);
h.btnDownload=criaBotao(fig,'Salvar ensaio',[956 130 163 30], ...
    @btnDownload_Callback,btnCol,textCol);

registro=uipanel('Parent',fig,'Units','pixels','Position',[16 14 1148 110], ...
    'BackgroundColor',bgPanel,'BorderType','none');
criaTexto(registro,'REGISTRO DE EVENTOS',[12 82 220 20],10,azul,bgPanel);
h.console=uicontrol('Parent',registro,'Style','listbox', ...
    'String',{'Selecione a porta serial e conecte. Gráficos aguardando dados.'}, ...
    'BackgroundColor',inputCol,'ForegroundColor',textCol, ...
    'FontName','Courier New','FontSize',9,'Position',[12 12 788 65]);
criaTexto(registro,'Comando manual',[820 82 180 20],10,textCol,bgPanel);
h.editComandoManual=uicontrol('Parent',registro,'Style','edit', ...
    'String','','BackgroundColor',inputCol,'ForegroundColor',textCol, ...
    'TooltipString','Comandos avançados. Para ajustar valores, use o botão Parâmetros Simulink.', ...
    'Position',[820 48 172 28]);
h.btnComandoManual=criaBotao(registro,'Enviar',[1002 48 132 28], ...
    @btnComandoManual_Callback,btnCol,textCol);
h.btnLimpar=criaBotao(registro,'Limpar registros',[1002 12 132 28], ...
    @btnLimpar_Callback,btnCol,textCol);

atualizarCamposHabilitados();
atualizarRotuloCompensador();
uiControles = findall(fig,'Type','uicontrol');
uiPaineis = findall(fig,'Type','uipanel');
set(uiControles,'Units','normalized');
set(uiPaineis,'Units','normalized');
set([h.ax1 h.ax2],'Units','normalized');
set([h.leg1 h.leg2],'Units','normalized');
set(h.leg1,'Position',[899/1180 531/720 220/1180 24/720]);
set(h.leg2,'Position',[1019/1180 322/720 100/1180 22/720]);

uiFontHandles = findall(fig,'-property','FontSize');
uiFontSizes = zeros(size(uiFontHandles));
for iFonte = 1:numel(uiFontHandles)
    set(uiFontHandles(iFonte),'FontUnits','points');
    uiFontSizes(iFonte) = get(uiFontHandles(iFonte),'FontSize');
end

unidadesRaiz = get(0,'Units');
set(0,'Units','pixels');
tela = get(0,'ScreenSize');
set(0,'Units',unidadesRaiz);
escalaInicial = min([1, (tela(3)-60)/1180, (tela(4)-120)/720]);
larguraJanela = max(1, floor(1180*escalaInicial));
alturaJanela = max(1, floor(720*escalaInicial));
set(fig,'Position',[tela(1)+(tela(3)-larguraJanela)/2, ...
    tela(2)+(tela(4)-alturaJanela)/2, larguraJanela, alturaJanela]);
set(fig,'ResizeFcn',@redimensionarInterface);
redimensionarInterface([],[]);
set(fig,'Visible','on');
movegui(fig,'onscreen');

    % Reposiciona os componentes conforme as dimensoes atuais da janela.
    function redimensionarInterface(~,~)
        if ~ishandle(fig), return; end
        posJanela = get(fig,'Position');
        escala = min(posJanela(3)/1180, posJanela(4)/720);
        escala = min(1.4, max(0.1, escala));
        for iFonteLocal = 1:numel(uiFontHandles)
            if ishandle(uiFontHandles(iFonteLocal))
                set(uiFontHandles(iFonteLocal),'FontSize', ...
                    uiFontSizes(iFonteLocal)*escala);
            end
        end
        set(h.ax1,'Position',[260/1180 382/720 859/1180 142/720]);
        set(h.ax2,'Position',[260/1180 210/720 859/1180 104/720]);
        set(h.leg1,'Position',[899/1180 531/720 220/1180 24/720]);
        set(h.leg2,'Position',[1019/1180 322/720 100/1180 22/720]);
        compactarLegenda(h.leg1);
        compactarLegenda(h.leg2);
    end

    function compactarLegenda(leg)
        limites = get(leg,'XLim');
        xInicio = limites(1) + 0.07*diff(limites);
        xFim = limites(1) + 0.22*diff(limites);
        tracos = findall(leg,'Type','line');
        for j = 1:numel(tracos)
            if leg == h.leg1
                corTraco = get(tracos(j),'Color');
                inicio = 0.03;
                if ~isequal(corTraco,[1 0 0]), inicio = 0.48; end
                xInicio = limites(1) + inicio*diff(limites);
                xFim = limites(1) + (inicio+0.09)*diff(limites);
            end
            dadosX = get(tracos(j),'XData');
            if numel(dadosX) > 1
                set(tracos(j),'XData',linspace(xInicio,xFim,numel(dadosX)));
            elseif numel(dadosX) == 1
                set(tracos(j),'XData',(xInicio+xFim)/2);
            end
        end
        textos = findall(leg,'Type','text');
        for j = 1:numel(textos)
            if ~isempty(get(textos(j),'String'))
                set(textos(j),'Units','normalized');
                posTexto = get(textos(j),'Position');
                posTexto(1) = 0.28;
                if leg == h.leg1
                    posTexto(1) = 0.15;
                    if strcmp(get(textos(j),'String'),'Temperatura')
                        posTexto(1) = 0.60;
                    end
                end
                set(textos(j),'Color',[1 1 1]);
                set(textos(j),'Position',posTexto);
            end
        end
    end

    function obj=criaTexto(pai,txt,pos,tamanho,cor,fundo)
        obj=uicontrol('Parent',pai,'Style','text','Units','pixels', ...
            'String',txt,'Position',pos,'FontSize',tamanho,'FontName','Arial', ...
            'HorizontalAlignment','left','ForegroundColor',cor, ...
            'BackgroundColor',fundo);
    end

    function obj=criaBotao(pai,txt,pos,callback,fundo,cor)
        obj=uicontrol('Parent',pai,'Style','pushbutton','Units','pixels', ...
            'String',txt,'Position',pos,'FontSize',10,'FontName','Arial', ...
            'FontWeight','bold','BackgroundColor',fundo, ...
            'ForegroundColor',cor,'Callback',callback);
    end

    function popupRotina_Callback(~,~)
        atualizarCamposHabilitados();
        atualizarRotuloCompensador();
    end

    % Exibe somente os campos usados pelo modo: referencia ou entrada manual.
    function atualizarCamposHabilitados()
        opcoes=get(h.popupRotina,'String');
        modo=opcoes{get(h.popupRotina,'Value')};

        TOPO = 325; PISO = 170;
        nAtivos = 0;
        for i=1:numel(h.edits)
            if campoAtivoNoModo(h.editKeys{i}, modo)
                nAtivos = nAtivos + 1;
            end
        end
        passo = 38; alturaCampo = 29; corpoFonte = 10;
        if nAtivos > 1
            passoMax = floor((TOPO - PISO) / (nAtivos - 1));
            if passoMax < passo
                passo = max(22, passoMax);
                alturaCampo = min(29, max(19, passo - 3));
                if alturaCampo < 26
                    corpoFonte = 9;
                end
            end
        end

        linha=0;
        for i=1:numel(h.edits)
            ativo=campoAtivoNoModo(h.editKeys{i},modo);
            if ativo
                vis='on';
                y=TOPO-linha*passo;
                deslocaRotulo = (alturaCampo - 20) / 2;
                set(h.fieldLabels(i),'Units','normalized','Position', ...
                    [8/171 (y+deslocaRotulo)/505 64/171 20/505]);
                set(h.edits(i),'Units','normalized','Position', ...
                    [76/171 y/505 54/171 alturaCampo/505], ...
                    'FontSize',corpoFonte);
                set(h.fieldUnits(i),'Units','normalized','Position', ...
                    [134/171 (y+deslocaRotulo)/505 32/171 20/505]);
                linha=linha+1;
            else
                vis='off';
            end
            set(h.edits(i),'Enable',vis,'Visible',vis);
            set(h.fieldLabels(i),'Visible',vis);
            set(h.fieldUnits(i),'Visible',vis);
        end

        set(h.txtCompensador,'Visible','on');
        set(h.btnSimular,'Visible','on','Enable','on');
    end

    function ativo = campoAtivoNoModo(chave, modo)
        ativo=strcmp(chave,'C') || (strcmp(chave,'V') && strcmp(modo,'Malha aberta')) ...
            || (strcmp(chave,'R') && strcmp(modo,'Controlador Simulink'));
    end

    function atualizarRotuloCompensador()
        if get(h.popupRotina,'Value')==2
            txt='Malha aberta: ajuste Entrada MV em volts.';
        else
            txt=sprintf('Simulink: %s\n%d parâmetros ajustáveis',perfil.nome,numel(perfil.nomes));
        end
        set(h.txtCompensador,'String',txt);
    end

    % Abre a serial e inicia a consulta do pacote; conectar nao inicia o ensaio.
    function btnConectar_Callback(~,~)
        if ~isConnected
            opcoes = get(h.popupPorta, 'String');
            idx = get(h.popupPorta, 'Value');
            portaEscolhida = opcoes{idx};

            if strcmp(portaEscolhida, 'Select...') || strcmp(portaEscolhida, 'Nenhuma porta encontrada')
                logMsg('[CONECTAR] Selecione uma porta COM válida antes de conectar.');
                return;
            end

            try
                serialObj = serial(portaEscolhida, ...
                    'BaudRate', 115200, ...
                    'DataBits', 8, ...
                    'Parity', 'none', ...
                    'StopBits', 1, ...
                    'Terminator', 'CR/LF', ...
                    'InputBufferSize', 4096,'Timeout',1);

                fopen(serialObj);
                pause(2); flushinput(serialObj);
                pacoteConferido=false;

                isConnected = true;
                set(h.btnConectar, 'String', 'DESCONECTAR');
                set(h.popupPorta, 'Enable', 'off'); % evita trocar a porta com a conexão aberta
                set(h.txtStatusRotina, 'String', ['Rotina: conectado em ' portaEscolhida '.']);
                logMsg(['[CONECTAR] Conectado com sucesso em ' portaEscolhida ' (115200 baud).']);


                serialTimer = timer(...
                    'ExecutionMode', 'fixedRate', ...
                    'Period', 0.3, ...
                    'TimerFcn', @(~,~) lerDadosSerial());
                start(serialTimer);
                enviarLinha('RUN,0'); pause(0.25); enviarLinha('INFO');

            catch erro
                logMsg(['[CONECTAR] ERRO ao abrir a porta: ' erro.message]);
                isConnected=false; pacoteConferido=false;
                if ~isempty(serialTimer) && isvalid(serialTimer), stop(serialTimer); delete(serialTimer); end
                serialTimer=[];
                set(h.btnConectar,'String','Conectar'); set(h.popupPorta,'Enable','on');
                if ~isempty(serialObj) && isvalid(serialObj)
                    delete(serialObj);
                end
                serialObj = [];
            end

        else
            try
                if ~isempty(serialTimer) && isvalid(serialTimer)
                    stop(serialTimer);
                    delete(serialTimer);
                end
                serialTimer = [];

                if ~isempty(serialObj) && isvalid(serialObj)
                    enviarLinha('RUN,0');
                    fclose(serialObj);
                    delete(serialObj);
                end
            catch erro
                logMsg(['[DESCONECTAR] Aviso ao fechar a porta: ' erro.message]);
            end

            envioSequencia=envioSequencia+1;
            serialObj = [];
            isConnected = false;
            pacoteConferido=false;
            valoresParametros(:)=NaN; parametroPendente=0; aguardandoLista=false;
            relogioParametros=[];
            atualizarJanelaParametros();
            set(h.btnConectar, 'String', 'CONECTAR');
            set(h.popupPorta, 'Enable', 'on');
            set(h.txtStatusRotina, 'String', 'Rotina: HVAC desconectado.');
            logMsg('[DESCONECTAR] Porta serial fechada.');
        end
    end

    % Valida os campos e envia configuracao, modo e solicitacao RUN,1.
    % O contador de sequencia permite cancelar esse envio ao solicitar parada.
    function btnAtualizar_Callback(~,~)
        if ~isConnected || ~pacoteConferido
            logMsg('[APLICAR] Conecte e aguarde a conferência do pacote.'); return;
        end
        envioSequencia=envioSequencia+1; minhaSequencia=envioSequencia;
        escolha=get(h.popupRotina,'Value');
        if escolha<2, logMsg('[APLICAR] Selecione Malha aberta ou Controlador Simulink.'); return; end
        valores=zeros(1,numel(h.edits));
        for j=1:numel(h.edits)
            valores(j)=str2double(get(h.edits(j),'String'));
            if strcmp(get(h.edits(j),'Enable'),'off'), continue; end
            chave=h.editKeys{j}; v=valores(j);
            if ~isfinite(v) || v<0 || (strcmp(chave,'R') && v>=55) || ...
                    (strcmp(chave,'V') && v>12) || (strcmp(chave,'C') && v>24)
                logMsg('[APLICAR] Confira R (0 a menos de 55), MV (0 a 12 V) e cooler (0 a 24 V).'); return;
            end
        end
        for j=1:numel(h.edits)
            if strcmp(get(h.edits(j),'Enable'),'off'), continue; end
            if minhaSequencia~=envioSequencia || ~isConnected, return; end
            enviarComando(h.editKeys{j},sprintf('%.8g',valores(j)));
            pause(0.25);
        end
        codigo='0'; if escolha==3, codigo='1'; end
        if minhaSequencia~=envioSequencia || ~isConnected, return; end
        enviarComando('M',codigo); pause(0.25);
        if minhaSequencia~=envioSequencia || ~isConnected, return; end
        enviarLinha('RUN,1');
        logMsg('[APLICAR] Confira as respostas do firmware. PARAR PLANTA interrompe o ensaio.');
    end

    function enviarComando(chave, valorStr)
        enviarLinha([chave ',' valorStr]);
    end

    function enviarLinha(comando)
        if isempty(serialObj) || ~isvalid(serialObj) || ~isConnected, return; end
        try
            fwrite(serialObj,[comando char(10)]);
            logMsg(['[TX] ' comando]);
        catch erro
            logMsg(['[TX] ERRO: ' erro.message]);
        end
    end

    function btnDownload_Callback(~,~)
        % Salva o CSV e o log em dados/ensaios, relativo a raiz do projeto.
        pastaEnsaios = fullfile(raiz, 'dados', 'ensaios');
        if ~exist(pastaEnsaios, 'dir')
            mkdir(pastaEnsaios);
        end
        [nomeArquivo, pasta] = uiputfile( ...
            {'*.csv', 'Arquivos CSV (*.csv)'}, ...
            'Salvar dados e log como...', ...
            fullfile(pastaEnsaios, 'hvac_dados.csv'));
        if isequal(nomeArquivo, 0)
            return; % usuário cancelou a caixa de diálogo
        end

        [~, nomeBase, ~] = fileparts(nomeArquivo);
        caminhoCsv = fullfile(pasta, [nomeBase '.csv']);
        caminhoTxt = fullfile(pasta, [nomeBase '_log.txt']);

        if isempty(dataLog)
            logMsg('[DOWNLOAD] Nenhum dado numérico registrado ainda (dataLog vazio).');
        else
            try
                fidCsv = fopen(caminhoCsv, 'w');
                fprintf(fidCsv, 'timestamp,modo,setpoint,temperatura,controle,jitter_control_us,jitter_sensor_us\n');
                fprintf(fidCsv, '%f,%d,%f,%f,%f,%f,%f\n', dataLog');
                fclose(fidCsv);
                logMsg(['[DOWNLOAD] Dados salvos em: ' caminhoCsv]);
            catch erro
                logMsg(['[DOWNLOAD] ERRO ao salvar CSV: ' erro.message]);
            end
        end

        try
            linhasConsole = get(h.console, 'String');
            if ischar(linhasConsole)
                linhasConsole = {linhasConsole};
            end
            fidTxt = fopen(caminhoTxt, 'w');
            fprintf(fidTxt,'Modelo Simulink: %s | ID: %s\n',perfil.nome,perfil.id);
            for i = 1:numel(linhasConsole)
                fprintf(fidTxt, '%s\n', linhasConsole{i});
            end
            fclose(fidTxt);
            logMsg(['[DOWNLOAD] Log salvo em: ' caminhoTxt]);
        catch erro
            logMsg(['[DOWNLOAD] ERRO ao salvar log: ' erro.message]);
        end
    end

    % Acesso direto ao protocolo; comandos continuam sujeitos ao firmware.
    function btnComandoManual_Callback(~,~)
        if ~isConnected, logMsg('[MANUAL] Conecte antes de enviar.'); return; end
        txt=strtrim(get(h.editComandoManual,'String'));
        if isempty(txt), return; end
        if numel(txt)>47 || any(txt==char(10)) || any(txt==char(13))
            logMsg('[MANUAL] Use uma linha de até 47 caracteres.'); return;
        end
        if ~pacoteConferido && ~any(strcmp(txt,{'INFO','RUN,0'}))
            logMsg('[MANUAL] Aguarde a conferência do pacote.'); return;
        end
        if (parametroPendente>0 || aguardandoLista) && ~strcmp(txt,'RUN,0')
            logMsg('[PARÂMETRO] Aguarde a operação da janela de parâmetros terminar.'); return;
        end
        if strncmp(txt,'PAR,',4)
            partes=regexp(txt,',','split');
            if numel(partes)~=3, logMsg('Use PAR,índice,valor.'); return; end
            i=str2double(partes{2}); v=str2double(partes{3});
            if ~isfinite(i) || i~=fix(i) || i<1 || i>numel(perfil.nomes) || ...
                    ~isfinite(v) || v<perfil.min(i) || v>perfil.max(i)
                logMsg('[MANUAL] Índice ou valor fora da faixa. Consulte Parâmetros Simulink.'); return;
            end
            % SET prepara e solicita a aplicacao atomica em uma unica mensagem.
            enviarLinha(['SET,' txt(5:end)]);
            logMsg('[PARÂMETRO] Aguarde [APLICADO]. Não precisa gravar novamente.');
        else
            if strcmp(txt,'RUN,0'), envioSequencia=envioSequencia+1; end
            enviarLinha(txt);
        end
    end

    % Abre a janela de parametros do controlador descrito no perfil importado.
    function btnSimular_Callback(~,~)
        if ~isempty(janelaParametros) && ishandle(janelaParametros)
            figure(janelaParametros); return;
        end
        janelaParametros=figure('Name','Parâmetros | Controlador Simulink', ...
            'NumberTitle','off','MenuBar','none','ToolBar','none', ...
            'Color',bgMain,'Resize','off','Units','pixels', ...
            'Position',[100 100 680 550],'Visible','off', ...
            'CloseRequestFcn',@fecharParametros);
        set(janelaParametros,'DefaultUicontrolFontName','Arial', ...
            'DefaultUicontrolFontSize',11);
        movegui(janelaParametros,'center');
        topo=uipanel('Parent',janelaParametros,'Units','pixels', ...
            'Position',[0 456 680 94],'BackgroundColor',bgTop,'BorderType','none');
        criaTexto(topo,'Parâmetros do controlador',[24 50 630 30],18,textCol,bgTop);
        criaTexto(topo,['Modelo: ' perfil.nome],[25 24 630 22],11,azul,bgTop);
        criaTexto(topo,'Os valores são consultados ao abrir; selecione um parâmetro para editar.', ...
            [25 3 630 21],10,cinza,bgTop);
        uiPar.tabela=uitable('Parent',janelaParametros,'Units','pixels', ...
            'Position',[24 271 632 168],'Data',cell(0,3), ...
            'ColumnName',{'Parâmetro','Valor no Arduino','Faixa permitida'}, ...
            'ColumnWidth',{220 160 225},'RowName',[], ...
            'ColumnEditable',[false false false], ...
            'FontName','Arial','FontSize',11, ...
            'ForegroundColor',[0.10 0.14 0.20], ...
            'BackgroundColor',[0.97 0.98 1;0.90 0.94 0.98], ...
            'CellSelectionCallback',@selecionarLinhaParametro);
        painel=uipanel('Parent',janelaParametros,'Units','pixels', ...
            'Position',[24 112 632 145],'BackgroundColor',bgPanel,'BorderType','none');
        criaTexto(painel,'PARÂMETRO',[16 110 370 22],10,cinza,bgPanel);
        criaTexto(painel,'NOVO VALOR',[409 110 200 22],10,cinza,bgPanel);
        nomes=perfil.nomes;
        if isempty(nomes), nomes={'Nenhum parâmetro exposto'}; end
        uiPar.selecao=uicontrol('Parent',painel,'Style','popupmenu', ...
            'Position',[16 73 374 34],'String',nomes,'Value',1, ...
            'BackgroundColor',[1 1 1],'ForegroundColor',[0.10 0.14 0.20], ...
            'FontSize',12,'Callback',@selecionarParametro);
        uiPar.valor=uicontrol('Parent',painel,'Style','edit', ...
            'Position',[409 73 207 34],'String','','HorizontalAlignment','left', ...
            'BackgroundColor',[1 1 1],'ForegroundColor',[0.10 0.14 0.20], ...
            'FontSize',13,'TooltipString','Aceita ponto ou vírgula decimal.');
        uiPar.detalhe=criaTexto(painel,'',[17 40 590 24],11,textCol,bgPanel);
        criaTexto(painel,'O novo valor é enviado sem regravar o Arduino.', ...
            [17 10 590 24],10,cinza,bgPanel);
        uiPar.aplicar=criaBotao(janelaParametros,'Aplicar valor', ...
            [230 63 220 36],@aplicarParametro,acaoCol,[1 1 1]);
        uiPar.status=criaTexto(janelaParametros,mensagemParametros, ...
            [25 5 630 50],11,cinza,bgMain);
        atualizarJanelaParametros();
        selecionarParametro([],[]);
        set(janelaParametros,'Visible','on');
        if isConnected && pacoteConferido && parametroPendente==0 && ~aguardandoLista
            consultarParametros([],[]);
        end
    end

    function fecharParametros(~,~)
        if ~isempty(janelaParametros) && ishandle(janelaParametros)
            delete(janelaParametros);
        end
        janelaParametros=[];
    end

    function selecionarLinhaParametro(~,evento)
        if isempty(evento.Indices) || isempty(perfil.nomes), return; end
        set(uiPar.selecao,'Value',evento.Indices(1,1));
        selecionarParametro([],[]);
    end

    function selecionarParametro(~,~)
        if isempty(perfil.nomes), return; end
        i=get(uiPar.selecao,'Value');
        if isfinite(valoresParametros(i))
            set(uiPar.valor,'String',sprintf('%.9g',valoresParametros(i)));
        else
            set(uiPar.valor,'String','');
        end
        atualizarJanelaParametros();
    end

    function atualizarJanelaParametros()
        if isempty(janelaParametros) || ~ishandle(janelaParametros), return; end
        dados=cell(numel(perfil.nomes),3);
        for k=1:numel(perfil.nomes)
            atual='Não consultado';
            if isfinite(valoresParametros(k)), atual=sprintf('%.9g',valoresParametros(k)); end
            dados(k,:)={perfil.nomes{k},atual,sprintf('%g a %g',perfil.min(k),perfil.max(k))};
        end
        set(uiPar.tabela,'Data',dados);
        pronto=(isConnected && pacoteConferido) && ~isempty(perfil.nomes);
        livre=parametroPendente==0 && ~aguardandoLista;
        set(uiPar.aplicar,'Enable',ternario(pronto && livre,'on','off'));
        set(uiPar.valor,'Enable',ternario(pronto && livre,'on','off'));
        set(uiPar.selecao,'Enable',ternario(~isempty(perfil.nomes),'on','off'));
        msg=mensagemParametros;
        if ~isConnected
            msg='Arduino desconectado. Conecte na janela principal.';
        elseif ~pacoteConferido
            msg='Aguardando a conferência do controlador conectado.';
        end
        if isempty(perfil.nomes)
            msg='Nenhum parâmetro ajustável. Exponha os parâmetros no Simulink e importe novamente.';
        else
            i=get(uiPar.selecao,'Value');
            set(uiPar.detalhe,'String',sprintf('Faixa permitida: %g a %g',perfil.min(i),perfil.max(i)));
        end
        set(uiPar.status,'String',msg);
    end

    % LISTAR consulta os valores atuais da placa, nao os valores do Workspace.
    function consultarParametros(~,~)
        if ~isConnected || ~pacoteConferido || parametroPendente~=0 || aguardandoLista, return; end
        valoresParametros(:)=NaN;
        aguardandoLista=true; relogioParametros=tic;
        mensagemParametros='Consultando os valores no Arduino...';
        atualizarJanelaParametros();
        enviarLinha('LISTAR');
    end

    % Valida o valor no perfil local e solicita SET; a confirmacao e assincrona.
    function aplicarParametro(~,~)
        if (~isConnected || ~pacoteConferido) || isempty(perfil.nomes) || ...
                parametroPendente~=0 || aguardandoLista, return; end
        i=get(uiPar.selecao,'Value');
        texto=strtrim(get(uiPar.valor,'String'));
        v=str2double(strrep(texto,',','.'));
        if ~isfinite(v) || v<perfil.min(i) || v>perfil.max(i)
            mensagemParametros=sprintf('Digite um número entre %g e %g.',perfil.min(i),perfil.max(i));
            atualizarJanelaParametros(); return;
        end
        parametroPendente=i; valorSolicitado=v; relogioParametros=tic;
        mensagemParametros=sprintf('Enviando %s = %.9g. Aguardando confirmação...',perfil.nomes{i},v);
        atualizarJanelaParametros();
        enviarLinha(sprintf('SET,%d,%.9g',i,v));
    end

    % APLICADO confirma a escrita na tarefa de Controle; depois LISTAR permite
    % conferir o valor efetivamente lido no Arduino antes de confirmar na GUI.
    function receberRespostaParametro(linha)
        if strncmp(linha,'[PAR],',6)
            q=regexp(linha,',','split');
            if numel(q)==3
                i=str2double(q{2}); v=str2double(q{3});
                if isfinite(i) && i==fix(i) && i>=1 && i<=numel(perfil.nomes) && isfinite(v)
                    valoresParametros(i)=v;
                end
            end
        elseif strcmp(linha,'[APLICADO]') && parametroPendente>0
            aguardandoLista=true; relogioParametros=tic;
            valoresParametros(:)=NaN;
            mensagemParametros='Arduino aplicou a alteração. Conferindo o valor...';
            enviarLinha('LISTAR');
        elseif strcmp(linha,'[LISTA_FIM]') && aguardandoLista
            aguardandoLista=false; relogioParametros=[];
            if parametroPendente>0
                i=parametroPendente;
                if isfinite(valoresParametros(i)) && abs(valoresParametros(i)-valorSolicitado)<=max(1e-6,abs(valorSolicitado)*1e-6)
                    mensagemParametros=sprintf('Confirmado: %s = %.9g.',perfil.nomes{i},valoresParametros(i));
                else
                    mensagemParametros='Valor solicitado não confirmado. Confira a tabela e o registro de eventos.';
                end
                parametroPendente=0;
            elseif all(isfinite(valoresParametros))
                mensagemParametros='Valores atualizados. Selecione um parâmetro para editar.';
            else
                mensagemParametros='Consulta incompleta. Feche e reabra esta janela para tentar novamente.';
            end
        elseif strncmp(linha,'[ERRO',5) && (parametroPendente>0 || aguardandoLista)
            parametroPendente=0; aguardandoLista=false; relogioParametros=[];
            mensagemParametros=['Arduino: ' linha];
        end
        atualizarJanelaParametros();
    end

    % Abre a analise offline dos arquivos, sem depender da conexao serial.
    function btnCompararSimulacao_Callback(~,~)
        addpath(raiz);
        comparar_simulacao_planta;
    end

    % Abre registros salvos para visualizacao, sem executar comandos na planta.
    function btnPlotarCSV_Callback(~,~)
        escolha = questdlg('Qual arquivo deseja abrir?', ...
            'Abrir ensaio / simulação', 'Ensaio CSV', 'Simulação MAT', ...
            'Cancelar', 'Ensaio CSV');
        if isempty(escolha) || strcmp(escolha,'Cancelar'), return; end

        if strcmp(escolha,'Ensaio CSV')
            pastaInicial = fullfile(raiz,'dados','ensaios');
            filtro = '*.csv';
            titulo = 'Abrir ensaio CSV';
        else
            pastaInicial = fullfile(raiz,'dados','simulacoes');
            filtro = '*.mat';
            titulo = 'Abrir simulação MAT';
        end
        if ~exist(pastaInicial,'dir'), mkdir(pastaInicial); end
        [nomeArquivo,pasta] = uigetfile(fullfile(pastaInicial,filtro),titulo);
        if isequal(nomeArquivo,0), return; end
        caminho = fullfile(pasta,nomeArquivo);

        try
            if strcmp(escolha,'Ensaio CSV')
                [M,nomes] = lerCsvEnsaio(caminho);
            else
                dadosMat = load(caminho);
                if isfield(dadosMat,'ensaio_simulacao')
                    registroSim = dadosMat.ensaio_simulacao;
                    if isfield(registroSim,'ref') && isfield(registroSim,'temp') && isfield(registroSim,'u')
                        ref = registroSim.ref;
                        temp = registroSim.temp;
                        u = registroSim.u;
                    else
                        error('Estrutura ensaio_simulacao incompleta.');
                    end
                elseif isfield(dadosMat,'ref_sim') && isfield(dadosMat,'temp_sim') && isfield(dadosMat,'u_sim')
                    ref = dadosMat.ref_sim;
                    temp = dadosMat.temp_sim;
                    u = dadosMat.u_sim;
                else
                    error('Arquivo MAT sem ref_sim, temp_sim e u_sim.');
                end
                t = double(temp.time(:));
                y = double(temp.signals.values(:));
                tr = double(ref.time(:));
                yr = double(ref.signals.values(:));
                tu = double(u.time(:));
                yu = double(u.signals.values(:));
                if numel(t)<2 || numel(t)~=numel(y) || ...
                        numel(tr)~=numel(yr) || numel(tu)~=numel(yu)
                    error('Vetores de tempo e sinais inconsistentes.');
                end
                if any(diff(t)<=0) || any(diff(tr)<=0) || any(diff(tu)<=0)
                    error('Tempo da simulação deve ser crescente.');
                end
                % Converter tempo (s) para timestamp (ms) usado pelo grafico CSV.
                % Interpolar apenas quando as bases de tempo forem diferentes.
                referencia = interp1(tr,yr,t,'linear',NaN);
                controle = interp1(tu,yu,t,'linear',NaN);
                M = [t*1000, y, referencia, controle];
                nomes = {'timestamp','temperatura','setpoint','controle'};
            end
        catch erro
            logMsg(['[PLOTAR] ERRO ao ler o arquivo: ' erro.message]);
            return;
        end

        if isempty(M) || size(M,1) < 2
            logMsg('[PLOTAR] O arquivo não tem linhas de dados suficientes.');
            return;
        end

        cTempo = acharColuna(nomes, 'timestamp');
        cTemp  = acharColuna(nomes, 'temperatura');
        cCtrl  = acharColuna(nomes, 'controle');
        cRef   = acharColuna(nomes, 'setpoint');
        if isempty(cTempo) || isempty(cTemp)
            logMsg('[PLOTAR] Não achei as colunas de tempo e temperatura no arquivo.');
            return;
        end

        tempoS = (M(:,cTempo) - M(1,cTempo)) / 1000;   % ms -> s, zerado no inicio
        temperatura = M(:,cTemp);

        fGraf = figure('Name', ['Ensaio: ' nomeArquivo], ...
                       'NumberTitle', 'off', ...
                       'Color', [1 1 1], ...
                       'Position', [150 120 900 620]);

        temControle = ~isempty(cCtrl);
        if temControle
            eixoT = subplot(2,1,1,'Parent',fGraf);
            eixoU = subplot(2,1,2,'Parent',fGraf);
        else
            eixoT = axes('Parent',fGraf);
            eixoU = [];
        end

        plot(eixoT, tempoS, temperatura, 'b-', 'LineWidth', 1.3);
        if ~isempty(cRef)
            hold(eixoT,'on');
            plot(eixoT, tempoS, M(:,cRef), 'k:', 'LineWidth', 1.2);
            hold(eixoT,'off');
            legend(eixoT, 'Temperatura', 'Setpoint', 'Location', 'southeast');
        else
            legend(eixoT, 'Temperatura', 'Location', 'southeast');
        end
        grid(eixoT,'on');
        ylabel(eixoT, 'Temperatura (\circC)');
        title(eixoT, nomeArquivo, 'Interpreter', 'none');
        if ~temControle
            xlabel(eixoT, 'Tempo (s)');
        end

        if temControle
            linhaControleCSV = plot(eixoU, tempoS, M(:,cCtrl), 'r-', 'LineWidth', 1.1);
            legendaControleCSV = legend(linhaControleCSV, 'Controle U', ...
                'Location', 'southeast');
            set(legendaControleCSV, 'Box', 'on', 'Color', [1 1 1], ...
                'FontWeight', 'normal');
            grid(eixoU,'on');
            xlabel(eixoU, 'Tempo (s)');
            ylabel(eixoU, 'Tensão na lâmpada (V)');
            linkaxes([eixoT eixoU], 'x');
        end
        xlim(eixoT, [tempoS(1) tempoS(end)]);

        btnPng = uicontrol('Parent',fGraf,'Style','pushbutton', ...
            'String','Salvar PNG (300 dpi)','FontWeight','bold', ...
            'Units','pixels','Position',[10 10 150 26]);
        btnPdf = uicontrol('Parent',fGraf,'Style','pushbutton', ...
            'String','Salvar PDF','FontWeight','bold', ...
            'Units','pixels','Position',[170 10 110 26]);
        set(btnPng,'Callback',@(~,~) exportarFigura(fGraf,[btnPng btnPdf],'png',nomeArquivo));
        set(btnPdf,'Callback',@(~,~) exportarFigura(fGraf,[btnPng btnPdf],'pdf',nomeArquivo));

        logMsg(sprintf('[PLOTAR] %s: %d linhas, %.1f s de ensaio.', ...
                       nomeArquivo, size(M,1), tempoS(end)));
    end

    function exportarFigura(fGraf, botoes, formato, nomeOrigem)
        [base, ~, ~] = fileparts(nomeOrigem);
        sugestao = [base '_grafico.' formato];
        [arq, pasta] = uiputfile(['*.' formato], 'Salvar figura como...', sugestao);
        if isequal(arq, 0)
            return;
        end
        destino = fullfile(pasta, arq);

        set(botoes, 'Visible', 'off');
        drawnow;
        try
            set(fGraf, 'PaperPositionMode', 'auto');
            if strcmp(formato, 'png')
                print(fGraf, '-dpng', '-r300', destino);
            else
                pp = get(fGraf, 'PaperPosition');
                set(fGraf, 'PaperSize', [pp(3) pp(4)]);
                print(fGraf, '-dpdf', '-r300', destino);
            end
            logMsg(['[PLOTAR] Figura salva em: ' destino]);
        catch erro
            logMsg(['[PLOTAR] ERRO ao salvar a figura: ' erro.message]);
        end
        set(botoes, 'Visible', 'on');
    end

    function [M, nomes] = lerCsvEnsaio(caminho)
        fid = fopen(caminho, 'r');
        if fid < 0
            error('nao consegui abrir o arquivo.');
        end
        primeira = fgetl(fid);
        if ~ischar(primeira)
            fclose(fid);
            error('arquivo vazio.');
        end
        partes = strtrim(strsplit(primeira, ','));
        temCabecalho = isnan(str2double(partes{1}));

        if temCabecalho
            nomes = cellfun(@lower, partes, 'UniformOutput', false);
        else
            frewind(fid);
            nomes = {'timestamp','modo','setpoint','temperatura','controle'};
            for iCol = 6:numel(partes)
                nomes{iCol} = sprintf('coluna%d', iCol);
            end
            nomes = nomes(1:numel(partes));
            logMsg('[PLOTAR] Arquivo sem cabeçalho: as 5 primeiras colunas foram assumidas na ordem padrão.');
        end

        nCols = numel(partes);
        bruto = textscan(fid, repmat('%f', 1, nCols), ...
                         'Delimiter', ',', 'CollectOutput', true, ...
                         'EmptyValue', NaN);
        fclose(fid);
        if isempty(bruto) || isempty(bruto{1})
            M = [];
        else
            M = bruto{1};
        end
    end

    function idx = acharColuna(nomes, alvo)
        idx = find(strcmpi(nomes, alvo), 1);
    end


    % Desenha as amostras acumuladas sem modificar os timestamps salvos.
    function atualizarGraficosComDadosReais()
        if isempty(dataLog) || size(dataLog,1) < 2
            return; % precisa de pelo menos 2 pontos para desenhar uma linha
        end

        % Tempo relativo ao primeiro ponto registrado: apos 'Limpar registros'
        % o grafico volta a comecar em 0 s (o CSV salvo mantem o timestamp original).
        tempoS          = (dataLog(:,1) - dataLog(1,1)) / 1000; % ms -> s
        setpointVals    = dataLog(:,3);
        temperaturaVals = dataLog(:,4);
        controleVals    = dataLog(:,5);

        set(h.linhaRef,  'XData', tempoS, 'YData', setpointVals);
        set(h.linhaTemp, 'XData', tempoS, 'YData', temperaturaVals);
        set(h.linhaU,    'XData', tempoS, 'YData', controleVals);

        xlim(h.ax1, [tempoS(1), tempoS(end) + 0.01]);
        xlim(h.ax2, [tempoS(1), tempoS(end) + 0.01]);

        combinadoTemp = [temperaturaVals; setpointVals];
        margemTemp = max(0.5, (max(combinadoTemp) - min(combinadoTemp)) * 0.1);
        ylim(h.ax1, [min(combinadoTemp) - margemTemp, max(combinadoTemp) + margemTemp]);

        margemU = max(0.5, (max(controleVals) - min(controleVals)) * 0.1);
        ylim(h.ax2, [min(controleVals) - margemU, max(controleVals) + margemU]);
    end

    function btnIdentificarAtual_Callback(~,~)
        % Chama identificar_planta_atraso com um ou mais CSVs em malha aberta.
        addpath(raiz);
        if exist('identificar_planta_atraso','file') ~= 2
            errordlg(['Arquivo identificar_planta_atraso.m não encontrado em: ' raiz], ...
                     'Identificar planta');
            return;
        end
        try
            logMsg('[IDENTIFICAR] Selecione um ou mais arquivos CSV de malha aberta.');
            resultadoIdentificacao = identificar_planta_atraso();
            m = resultadoIdentificacao.modelos;
            logMsg(sprintf('[IDENTIFICAR] Concluído: %d ensaio(s), L=%.6f s.', ...
                           numel(m.RMSE),m.L));
            for j=1:numel(m.RMSE)
                logMsg(sprintf('[IDENTIFICAR] %s: RMSE=%.4f C.', ...
                    resultadoIdentificacao.arquivos{j},m.RMSE(j)));
            end
            logMsg(['[IDENTIFICAR] Resultados: ' resultadoIdentificacao.pasta]);
            % Funcao de transferencia continua do modelo com atraso.
            tfTexto = sprintf([ ...
                'G(s) = exp(-%.6f*s) * (\n' ...
                '  %.6f/(%.6f*s + 1) +\n' ...
                '  %.6f/(%.6f*s + 1) +\n' ...
                '  %.6f/(%.6f*s + 1) )'], ...
                m.L,m.K(1),m.tau(1),m.K(2),m.tau(2),m.K(3),m.tau(3));
            logMsg(['[IDENTIFICAR] ' strrep(tfTexto,sprintf('\n'),' ')]);
            mostrarResultadoIdentificacao(m,resultadoIdentificacao.pasta,tfTexto);
        catch erro
            logMsg(['[IDENTIFICAR] ' erro.message]);
            errordlg(erro.message,'Erro na identificação');
        end
    end

    function mostrarResultadoIdentificacao(m,pastaResultados,tfTexto)
        % Janela personalizada, compativel com MATLAB R2014a.
        f=figure('Name','Identificação da planta - Resultados', ...
            'NumberTitle','off','MenuBar','none','ToolBar','none', ...
            'Color',[0.97 0.98 1], 'Units','pixels', ...
            'Position',[150 130 760 480], 'Resize','off');
        movegui(f,'center');
        uicontrol('Parent',f,'Style','text','Units','pixels', ...
            'Position',[25 441 710 25],'String','IDENTIFICAÇÃO DA PLANTA CONCLUÍDA', ...
            'BackgroundColor',[0.97 0.98 1], 'ForegroundColor',[0.08 0.24 0.39], ...
            'FontSize',14,'FontWeight','bold','HorizontalAlignment','left');
        uicontrol('Parent',f,'Style','text','Units','pixels', ...
            'Position',[25 414 710 20],'String','Função de transferência contínua - modelo com atraso', ...
            'BackgroundColor',[0.97 0.98 1], 'ForegroundColor',[0.25 0.32 0.40], ...
            'FontSize',10,'HorizontalAlignment','left');
        % Desenha as fracoes com objetos graficos compativeis com MATLAB R2014a.
        % Todas as parcelas ficam na horizontal, com fonte uniforme.
        corEq=[0.08 0.24 0.39];
        axEq=axes('Parent',f,'Units','pixels','Position',[28 292 704 104], ...
            'XLim',[0 704],'YLim',[0 104],'Visible','off');
        fonte='Helvetica';
        text(0,52,'G(s) =','Parent',axEq,'Interpreter','none', ...
            'FontName',fonte,'FontSize',12,'Color',corEq, ...
            'VerticalAlignment','middle');
        text(69,52,sprintf('e^{ -%.6f s }',m.L), ...
            'Parent',axEq,'Interpreter','none','FontName',fonte, ...
            'FontSize',11,'Color',corEq,'VerticalAlignment','middle');
        text(178,52,'(','Parent',axEq,'Interpreter','none', ...
            'FontName',fonte,'FontSize',20,'Color',corEq, ...
            'VerticalAlignment','middle');
        centros=[270 449 628];
        for ii=1:3
            xc=centros(ii);
            text(xc,68,sprintf('%.6f',m.K(ii)), ...
                'Parent',axEq,'Interpreter','none','FontName',fonte, ...
                'FontSize',11,'Color',corEq, ...
                'HorizontalAlignment','center','VerticalAlignment','middle');
            line([xc-69 xc+69],[53 53],'Parent',axEq, ...
                'Color',corEq,'LineWidth',1.1);
            text(xc,38,sprintf('%.6f s + 1',m.tau(ii)), ...
                'Parent',axEq,'Interpreter','none','FontName',fonte, ...
                'FontSize',11,'Color',corEq, ...
                'HorizontalAlignment','center','VerticalAlignment','middle');
            if ii<3
                text(xc+89,53,'+','Parent',axEq, ...
                    'Interpreter','none','FontName',fonte,'FontSize',15, ...
                    'Color',corEq,'HorizontalAlignment','center', ...
                    'VerticalAlignment','middle');
            end
        end
        text(702,52,')','Parent',axEq,'Interpreter','none', ...
            'FontName',fonte,'FontSize',20,'Color',corEq, ...
            'HorizontalAlignment','right','VerticalAlignment','middle');
        uicontrol('Parent',f,'Style','text','Units','pixels', ...
            'Position',[25 209 710 22],'String','PARÂMETROS IDENTIFICADOS', ...
            'BackgroundColor',[0.97 0.98 1],'ForegroundColor',[0.08 0.24 0.39], ...
            'FontSize',11,'FontWeight','bold','HorizontalAlignment','left');
        dadosTabela=cell(4,4);
        for ii=1:3
            dadosTabela{ii,1}=sprintf('Ramo %d',ii);
            dadosTabela{ii,2}=sprintf('%.6f',m.K(ii));
            dadosTabela{ii,3}=sprintf('%.6f',m.tau(ii));
            dadosTabela{ii,4}='';
        end
        dadosTabela(4,:)={'Atraso','-','-',sprintf('%.6f',m.L)};
        uitable('Parent',f,'Units','pixels','Position',[25 104 710 102], ...
            'Data',dadosTabela,'ColumnName',{'Componente','Ganho K (C/V)','Tau (s)','Atraso L (s)'}, ...
            'ColumnWidth',{165 165 165 165},'RowName',[],'ColumnEditable',[false false false false]);
        uicontrol('Parent',f,'Style','text','Units','pixels', ...
            'Position',[25 81 710 20],'String','Pasta dos resultados:', ...
            'BackgroundColor',[0.97 0.98 1], 'FontWeight','bold', ...
            'HorizontalAlignment','left');
        uicontrol('Parent',f,'Style','edit','Units','pixels', ...
            'Position',[25 55 710 24],'String',pastaResultados, ...
            'BackgroundColor','white','HorizontalAlignment','left', ...
            'Enable','inactive');
        uicontrol('Parent',f,'Style','pushbutton','Units','pixels', ...
            'Position',[350 12 220 33],'String','Copiar função de transferência', ...
            'FontSize',10,'Callback',@(~,~) clipboard('copy',tfTexto));
        uicontrol('Parent',f,'Style','pushbutton','Units','pixels', ...
            'Position',[585 12 150 33],'String','Fechar', ...
            'FontSize',10,'Callback',@(~,~) close(f));
    end

    function custo=custoFopdt(p,t,y,y0,du,dt,dur)
        K=exp(p(1));tau=exp(p(2));theta=p(3);
        if any(~isfinite(p))||~isfinite(K)||~isfinite(tau)||K<=0||tau<dt||tau>10*dur||theta<0||theta>0.8*dur
            custo=1e30;return;
        end
        yp=y0+K*du*(1-exp(-max(0,t-theta)/tau));
        custo=mean((y-yp).^2);
    end

    % Permite selecionar varios ensaios salvos para comparar suas curvas.
    function btnAnalisarMultiplos_Callback(~,~)
        pastaEnsaios = fullfile(raiz, 'dados', 'ensaios');
        if ~exist(pastaEnsaios, 'dir')
            mkdir(pastaEnsaios);
        end
        [arquivos,pasta] = uigetfile( ...
            {'*.csv', 'Arquivos CSV (*.csv)'}, ...
            'Selecione os ensaios (Ctrl+clique para varios)', ...
            fullfile(pastaEnsaios, '*.csv'), ...
            'MultiSelect', 'on');
        if isequal(arquivos,0),return;end
        if ischar(arquivos),arquivos={arquivos};end
        f=figure('Name','Comparar ensaios','NumberTitle','off','Color',[1 1 1]);
        ax1=subplot(2,1,1,'Parent',f);hold(ax1,'on');grid(ax1,'on');
        ax2=subplot(2,1,2,'Parent',f);hold(ax2,'on');grid(ax2,'on');
        cores=lines(numel(arquivos));l1=[];l2=[];n1={};n2={};validos=0;
        for i=1:numel(arquivos)
            try
                [M,nomes]=lerCsvEnsaio(fullfile(pasta,arquivos{i}));
                it=acharColuna(nomes,'timestamp');iy=acharColuna(nomes,'temperatura');
                iu=acharColuna(nomes,'controle');ir=acharColuna(nomes,'setpoint');
                if isempty(it)||isempty(iy)||isempty(iu),error('Faltam timestamp, temperatura ou controle.');end
                if size(M,1)<2,error('Menos de duas amostras.');end
                t=M(:,it)/1000;y=M(:,iy);u=M(:,iu);
                if any(~isfinite(t))||any(diff(t)<=0),error('Timestamps inválidos/repetidos ou reinício no arquivo. Separe os registros.');end
                if sum(isfinite(y))<2||sum(isfinite(u))<2,error('Poucos dados válidos.');end
                t=t-t(1);co=cores(i,:);
                l1(end+1)=plot(ax1,t,y,'Color',co,'LineWidth',1.5);n1{end+1}=[arquivos{i} ' - temperatura']; %#ok<AGROW>
                if ~isempty(ir)
                    l1(end+1)=plot(ax1,t,M(:,ir),'--','Color',co,'LineWidth',1);n1{end+1}=[arquivos{i} ' - referência']; %#ok<AGROW>
                end
                l2(end+1)=plot(ax2,t,u,'Color',co,'LineWidth',1.4);n2{end+1}=arquivos{i}; %#ok<AGROW>
                validos=validos+1;
                logMsg(sprintf('[COMPARAR] %s: %d amostras, %.2f s. Alinhado ao início do arquivo.',arquivos{i},size(M,1),t(end)));
            catch erro
                logMsg(sprintf('[COMPARAR] %s: %s',arquivos{i},erro.message));
            end
        end
        if validos==0,close(f);logMsg('[COMPARAR] Nenhum CSV válido. Confira as mensagens acima.');return;end
        xlabel(ax1,'Tempo desde o início de cada arquivo (s)');ylabel(ax1,'Temperatura (°C)');
        xlabel(ax2,'Tempo desde o início de cada arquivo (s)');ylabel(ax2,'Controle (V)');
        title(ax1,'Temperaturas e referências');title(ax2,'Ações de controle');
        legend(ax1,l1,n1,'Interpreter','none','Location','best');
        legend(ax2,l2,n2,'Interpreter','none','Location','best');
        linkaxes([ax1 ax2],'x');
        logMsg('[COMPARAR] Comparação visual pronta. Não estima nem calcula médias de modelos da planta.');
    end

    function resultado = ternario(condicao, valorSeVerdadeiro, valorSeFalso)
        if condicao
            resultado = valorSeVerdadeiro;
        else
            resultado = valorSeFalso;
        end
    end

    % Interrompe sequencias de partida em andamento e solicita RUN,0.
    function btnParar_Callback(~,~)
        envioSequencia=envioSequencia+1;
        if ~isConnected, return; end
        enviarLinha('RUN,0');
        for j=1:numel(h.edits)
            if any(strcmp(h.editKeys{j},{'V','C'})), set(h.edits(j),'String','0'); end
        end
        logMsg('[PARAR] Parada solicitada. Aguarde o comando aplicado chegar a zero.');
    end

    % Limpa memoria, graficos e eventos locais. Nao para a planta nem apaga
    % arquivos salvos; salve os registros necessarios antes de limpar.
    function btnLimpar_Callback(~,~)
        dataLog = zeros(0,7);
        set(h.console, 'String', {'Log limpo.'});
        set(h.console, 'Value', 1);  % sem isso, um Value antigo (de um log longo) fica fora do intervalo do texto novo
        set(h.linhaRef,  'XData', [], 'YData', []);
        set(h.linhaTemp, 'XData', [], 'YData', []);
        set(h.linhaU,    'XData', [], 'YData', []);
        xlim(h.ax1, [0 60]);
        xlim(h.ax2, [0 60]);
    end

    % Timer de supervisao: recebe linhas, acompanha timeout dos parametros
    % e atualiza os graficos a cada tres ciclos. Nao define o periodo do controle.
    function lerDadosSerial()
        if isempty(serialObj) || ~isvalid(serialObj) || ~isConnected
            return;
        end

        try
            while serialObj.BytesAvailable > 0
                linha = fgetl(serialObj); % lê até o Terminator (CR/LF)
                if ischar(linha) && ~isempty(linha)
                    processarLinhaCSV(linha);
                end
            end
        catch erro
            logMsg(['[SERIAL] Erro na leitura: ' erro.message]);
            return;
        end

        if ~isempty(relogioParametros) && toc(relogioParametros)>5
            parametroPendente=0; aguardandoLista=false; relogioParametros=[];
            valoresParametros(:)=NaN;
            mensagemParametros='Sem confirmação. Feche e reabra esta janela para consultar novamente.';
            atualizarJanelaParametros();
        end
        contadorTimer = contadorTimer + 1;
        if contadorTimer >= 3
            contadorTimer = 0;
            atualizarGraficosComDadosReais();
        end
    end

    % Encaminha respostas do protocolo e telemetria. INFO/HELLO conferem
    % a correspondencia entre o perfil local e o pacote gravado no Arduino.
    function processarLinhaCSV(linha)
        linhaLimpa = strtrim(linha);
        if ~isempty(linhaLimpa) && linhaLimpa(1)=='['
            receberRespostaParametro(linhaLimpa);
        end
        if strncmp(linhaLimpa,'[INFO],',7)
            q=regexp(linhaLimpa,',','split');
            pacoteConferido=false;
            valoresParametros(:)=NaN; parametroPendente=0; aguardandoLista=false;
            relogioParametros=[];
            atualizarJanelaParametros();
            if numel(q)==5 && strcmp(q{2},perfil.id) && str2double(q{3})==numel(perfil.nomes) ...
                    && abs(str2double(q{4})-perfil.Ts)<1e-9 && strcmp(q{5},'MA_SIM_3')
                enviarLinha(['HELLO,' perfil.id]);
            else
                enviarLinha('RUN,0');
                logMsg('[PACOTE] Firmware e perfil diferentes. Grave a versão correta e reabra a GUI.');
            end
        elseif strcmp(linhaLimpa,'[HELLO],1')
            pacoteConferido=true;
            atualizarJanelaParametros();
            if ~isempty(janelaParametros) && ishandle(janelaParametros)
                consultarParametros([],[]);
            end
            logMsg('[PACOTE] Conferido. Selecione o modo e clique em Aplicar / iniciar.');
        elseif strncmp(linhaLimpa,'D,',2)
            q=regexp(linhaLimpa,',','split');
            if numel(q)~=9, return; end
            modoReal=str2double(q{2}); codigoFalha=str2double(q{9});
            if codigoFalha~=ultimaFalha
                if codigoFalha>0, logMsg(sprintf('[FALHA] Código %g; ensaio interrompido.',codigoFalha)); end
                ultimaFalha=codigoFalha;
            end
            if modoReal==0, st='Ativo: Malha Aberta';
            elseif modoReal==1, st='Ativo: Simulink'; else st='Planta parada'; end
            set(h.txtStatusRotina,'String',st);
            linha=sprintf('%s,%s,%s,%s,%s,%s,%s',q{2:8});
        end
        if ~isempty(linhaLimpa) && linhaLimpa(1) == '['
            logMsg(['[FW] ' linhaLimpa]);
            return;
        end

        campos = strsplit(linha, ',');

        if numel(campos) < 6 || numel(campos) > 8
            return;
        end

        modo        = str2double(campos{1});
        setpoint    = str2double(campos{2});
        temperatura = str2double(campos{3});
        controle    = str2double(campos{4});
        jitterUs = NaN;
        jitterSensorUs = NaN;
        if numel(campos) == 7
            timestamp      = str2double(campos{5});
            jitterUs       = str2double(campos{6});
            jitterSensorUs = str2double(campos{7});
        else
            timestamp = str2double(campos{6});
            if numel(campos) >= 7, jitterUs       = str2double(campos{7}); end
            if numel(campos) >= 8, jitterSensorUs = str2double(campos{8}); end
        end

        if any(isnan([modo, setpoint, controle, timestamp]))
            logMsg(['[SERIAL] Linha ignorada (valor inválido/NaN): ' linha]);
            return;
        end

        if isnan(temperatura)
            set(h.indicadores(1), 'String', 'SEM MEDIDA');
            if ~avisouSemMedida
                logMsg('[SERIAL] Sem leitura de temperatura (sensor sem resposta ou inicialização). Linhas omitidas até a leitura voltar.');
                avisouSemMedida = true;
            end
            return;
        end
        if avisouSemMedida
            logMsg('[SERIAL] Medida de temperatura retomada.');
            avisouSemMedida = false;
        end

        set(h.indicadores(1), 'String', sprintf('%.2f °C', temperatura));
        set(h.indicadores(2), 'String', sprintf('%.2f °C', setpoint));
        set(h.indicadores(3), 'String', sprintf('%.2f V', controle));
        dataLog(end+1, :) = [timestamp, modo, setpoint, temperatura, controle, jitterUs, jitterSensorUs]; %#ok<AGROW>
    end

    function logMsg(msg)
        atual = get(h.console, 'String');
        if ischar(atual)
            atual = {atual};
        end
        atual{end+1} = msg;
        set(h.console, 'String', atual);
        set(h.console, 'Value', numel(atual));
    end

    % Solicita parada e libera os timers e a porta serial ao fechar a interface.
    function fecharJanela_Callback(~,~)
        envioSequencia=envioSequencia+1;
        try
            if ~isempty(serialTimer) && isvalid(serialTimer)
                stop(serialTimer);
                delete(serialTimer);
            end
        catch
        end
        if isConnected && ~isempty(serialObj) && isvalid(serialObj)
            try
                enviarLinha('RUN,0');
                fclose(serialObj);
                delete(serialObj);
            catch
            end
        end
        fecharParametros([],[]);
        delete(fig);
    end

end

% Enumera as portas disponiveis usando os recursos presentes no ambiente.
function portas = listarPortasSeriais()

    portasEncontradas = {};

    if ispc
        try
            [status, resultado] = system('reg query "HKLM\HARDWARE\DEVICEMAP\SERIALCOMM"');
            if status == 0
                tokens = regexp(resultado, 'COM\d+', 'match');
                portasEncontradas = unique(tokens);
            end
        catch
            portasEncontradas = {};
        end
    end

    if isempty(portasEncontradas)
        try
            info = instrhwinfo('serial');
            portasEncontradas = info.SerialPorts;
        catch
            portasEncontradas = {};
        end
    end

    if isempty(portasEncontradas)
        portas = {'Nenhuma porta encontrada'};
    else
        portas = [{'Select...'}, portasEncontradas];
    end
end

% Le o perfil gerado pelo importador: ID, nome, periodo e faixas de parametros.
function p=lerPerfil(arq)
f=fopen(arq,'r'); if f<0, error('Perfil ausente. Execute importar_controlador.'); end
c=onCleanup(@() fclose(f));
t=regexp(fgetl(f),'\t','split');
p=struct('id',t{1},'nome',t{2},'Ts',str2double(t{3}),'nomes',{{}},'min',[],'max',[]);
while ~feof(f)
    l=fgetl(f); if ~ischar(l) || isempty(l), continue; end
    t=regexp(l,'\t','split'); p.nomes{end+1}=t{1}; p.min(end+1)=str2double(t{2}); p.max(end+1)=str2double(t{3});
end
end
