function comparar_simulacao_planta(matSim,csvReal)
% COMPARAR_SIMULACAO_PLANTA Compara os registros da simulacao e da planta.
%
% Uso: comparar_simulacao_planta abre a selecao do CSV e depois do MAT.
%      comparar_simulacao_planta(matSim, csvReal) recebe os caminhos diretamente.
% Observe que a ordem dos argumentos difere da ordem das janelas de selecao.
% Analise offline compativel com MATLAB R2014a, sem acesso a serial ou Simulink.
%
% Separa trechos continuos em modo 0 ou 1. Em malha aberta, tenta alinhar
% transicoes correspondentes do comando; nos demais casos usa o inicio dos
% registros. A versao atual usa temperatura absoluta e offset igual a zero.
% Apresenta curvas, erros e indicadores de resposta. Permite salvar resultados
% e graficos em dados/comparacoes. Os detalhes informam os criterios aplicados.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz
raizProjeto=fileparts(mfilename('fullpath'));
pastaEnsaios=fullfile(raizProjeto,'dados','ensaios');
pastaSimulacoes=fullfile(raizProjeto,'dados','simulacoes');
if ~exist(pastaEnsaios,'dir'), mkdir(pastaEnsaios); end
if ~exist(pastaSimulacoes,'dir'), mkdir(pastaSimulacoes); end
if nargin<2 || isempty(csvReal)
    [n,p]=uigetfile(fullfile(pastaEnsaios,'*.csv'),'1 - Selecione o CSV do ensaio da planta');
    if isequal(n,0), return; end
    csvReal=fullfile(p,n);
end
if nargin<1 || isempty(matSim)
    [n,p]=uigetfile(fullfile(pastaSimulacoes,'*.mat'),'2 - Selecione a simulação exportada');
    if isequal(n,0), return; end
    matSim=fullfile(p,n);
end
try
    d=load(matSim);
    if isfield(d,'ensaio_simulacao')
        sim=d.ensaio_simulacao;
    elseif all(isfield(d,{'ref_sim','temp_sim','u_sim'}))
        sim=struct('ref',d.ref_sim,'temp',d.temp_sim,'u',d.u_sim,'meta',struct());
    else
        error('O arquivo MAT precisa conter ensaio_simulacao ou ref_sim, temp_sim e u_sim.');
    end
    m=lerCSV(csvReal);
    % Cada partida, modo, reinicio do relogio ou lacuna grande gera outro trecho.
    dt=diff(m(:,1)); bons=dt(dt>0 & isfinite(dt));
    if isempty(bons), error('CSV sem intervalo de tempo válido.'); end
    limite=max(1000,5*median(bons));
    ativo=(m(:,2)==1 | m(:,2)==0) & all(isfinite(m),2);
    segmentos={}; rotulos={}; i=1;
    while i<=size(m,1)
        if ~ativo(i), i=i+1; continue; end
        j=i;
        while j<size(m,1) && ativo(j+1) && m(j+1,2)==m(i,2) && ...
                m(j+1,1)>m(j,1) && m(j+1,1)-m(j,1)<=limite
            j=j+1;
        end
        if j>i
            segmentos{end+1}=m(i:j,:);
            rotulos{end+1}=sprintf('%d | modo %g | %.2f a %.2f s no CSV | %.1f s de duracao', ...
                numel(segmentos),m(i,2),m(i,1)/1000,m(j,1)/1000,(m(j,1)-m(i,1))/1000);
        end
        i=j+1;
    end
    if isempty(segmentos), error('Nenhum trecho contínuo em modo 0 ou 1 com dados válidos.'); end
    if numel(segmentos)==1
        % Um unico trecho: seleciona automaticamente, sem janela redundante.
        k=1;
    else
        % Varios trechos: o usuario escolhe qual ensaio comparar.
        [k,ok]=listdlg('PromptString','Escolha um único ensaio (1 = Simulink; 0 = malha aberta)', ...
            'SelectionMode','single','ListString',rotulos,'ListSize',[640 180]);
        if ~ok, return; end
    end
    trecho=segmentos{k};
    % Converte timestamp de ms para segundos, relativo ao inicio do trecho.
    real=[(trecho(:,1)-trecho(1,1))/1000 trecho(:,3:5)];
    [op,automatico,notaAlinhamento]=alinhamento_automatico_hvac(sim,real,trecho(1,2));
    if automatico
        fprintf('%s\n',notaAlinhamento);
    else
        % Padrao: alinha o inicio do trecho real ao inicio da simulacao (t=0).
        % A comparacao ja verifica e alerta se as referencias forem diferentes.
        op=struct('zero_real',0,'zero_sim',0,'offset_temperatura',0, ...
            'metodo_alinhamento','início_dos_registros', ...
            'observacao_alinhamento',['Alinhamento pelo início dos registros (t=0 em ambos). ' notaAlinhamento]);
        fprintf('%s\n',op.observacao_alinhamento);
    end
    if trecho(1,2)==0
        avisoMA=['Ensaio em malha aberta: sincronizacao pelo comando u, nao pela referencia. ' ...
            'Métricas de seguimento da referência não avaliam a identificação da planta.'];
        fprintf('%s\n',avisoMA);
        op.observacao_alinhamento=[op.observacao_alinhamento ' ' avisoMA];
    end
    % O modelo atual ja inclui a temperatura inicial e fornece temperatura absoluta.
    % A comparacao utiliza temperatura absoluta, sem somar uma base adicional.
    tipo=1;
    op.offset_temperatura=0;
    if any(~isfinite([op.zero_real op.zero_sim op.offset_temperatura]))
        error('Informe valores numericos finitos.');
    end
    if op.zero_real<real(1,1) || op.zero_real>real(end,1) || ...
            op.zero_sim<sim.ref.time(1) || op.zero_sim>sim.ref.time(end)
        error('O evento escolhido deve estar dentro do intervalo registrado.');
    end
    resultado=calcular_comparacao_hvac(sim,real,op);
    resultado.arquivo_simulacao=matSim; resultado.arquivo_planta=csvReal;
    resultado.trecho=rotulos{k}; resultado.dados_reais_trecho=trecho;
    resultado.simulacao_original=sim; resultado.tipo_temperatura=tipo;
    mostrar(resultado);
catch erro
    errordlg(erro.message,'Comparação não realizada');
end
end

function v=numero(t)
v=str2double(strrep(strtrim(t),',','.'));
end

% Localiza as cinco colunas pelo cabecalho; outras colunas nao entram no calculo.
function m=lerCSV(arq)
f=fopen(arq,'r'); if f<0, error('Não foi possível abrir o CSV.'); end
limpa=onCleanup(@() fclose(f));
cab=fgetl(f); if ~ischar(cab), error('CSV vazio.'); end
cab=regexprep(cab,'[^\x20-\x7E]','');
nomes=regexp(lower(strtrim(cab)),',','split');
esperados={'timestamp','modo','setpoint','temperatura','controle'}; cols=zeros(1,5);
for k=1:5
    z=find(strcmp(strtrim(nomes),esperados{k}),1);
    if isempty(z), error('Coluna obrigatória ausente: %s.',esperados{k}); end
    cols(k)=z;
end
d=textscan(f,repmat('%f',1,numel(nomes)),'Delimiter',',', ...
    'CollectOutput',true,'TreatAsEmpty',{'nan','NaN'},'ReturnOnError',false);
if isempty(d) || isempty(d{1}), error('CSV sem dados numéricos.'); end
m=d{1}(:,cols);
end

function mostrar(r)
% Apresentacao compativel com os graficos HG1 do MATLAB R2014a.
fundo=[.95 .97 .98]; tinta=[.12 .20 .29]; azul=[.08 .40 .72]; laranja=[.90 .36 .10];
tela=get(0,'ScreenSize');
w=min(1280,tela(3)-60); hh=min(820,tela(4)-100);
f=figure('Name','Comparação | Simulação e planta','NumberTitle','off', ...
    'Color',fundo,'Position',[30 50 w hh],'MenuBar','none','ToolBar','figure');
movegui(f,'center');
texto(f,[.04 .932 .92 .045],'SIMULAÇÃO E PLANTA',19,tinta,fundo,'bold');
texto(f,[.04 .897 .92 .03],'Resposta térmica e sinal de controle no mesmo intervalo de tempo',10,tinta,fundo,'normal');
rotulos={'RMSE DA TEMPERATURA','ERRO MÁXIMO ABSOLUTO','ERRO MÉDIO COM SINAL'};
valores={sprintf('%.3f °C',r.rmse),sprintf('%.3f °C',r.erro_max),sprintf('%+.3f °C',r.vies)};
for j=1:3
    p=uipanel('Parent',f,'Units','normalized','Position',[.04+(j-1)*.222 .782 .210 .102], ...
        'BackgroundColor','w','BorderType','line','HighlightColor',[.82 .87 .90]);
    texto(p,[.05 .65 .91 .25],rotulos{j},9,tinta,[1 1 1],'bold');
    texto(p,[.05 .10 .91 .48],valores{j},20,azul,[1 1 1],'bold');
end
panel=uipanel('Parent',f,'Units','normalized','Position',[.745 .205 .225 .678], ...
    'BackgroundColor','w','BorderType','line','HighlightColor',[.82 .87 .90]);
texto(panel,[.06 .92 .88 .055],'DADOS DA COMPARAÇÃO',11,tinta,[1 1 1],'bold');
[~,ns,es]=fileparts(r.arquivo_simulacao);[~,nr,er]=fileparts(r.arquivo_planta);
modo='Simulink';if r.dados_reais_trecho(1,2)==0,modo='Malha aberta';end
rep='Temperatura absoluta';if r.tipo_temperatura==2,rep='Variação + temperatura de operação';end
info=sprintf(['SIMULAÇÃO (MAT)\n%s%s\n\nPLANTA (CSV)\n%s%s\n\n' ...
    'Modo: %s\nIntervalo: %.2f a %.2f s\nDuracao comparada: %.2f s\nAmostras: %d\nMAE: %.3f C\n\n' ...
    'ALINHAMENTO\nEvento real: %.3f s no trecho\nEvento simulado: %.3f s\nOffset de temperatura: %+.3f C\n%s\n\n' ...
    'Diferença máxima entre\nreferências: %.3f °C\n\n' ...
    'Erro = planta - simulação.\nPositivo: planta mais quente.\n\nMétricas por amostra.\nTemperatura interpolada linearmente;\ncomando e referência por retenção.'], ...
    ns,es,nr,er,modo,r.intervalo(1),r.intervalo(2),diff(r.intervalo),r.n_amostras,r.mae, ...
    r.opcoes.zero_real,r.opcoes.zero_sim,r.opcoes.offset_temperatura,rep,r.diferenca_referencia_max);
if isfield(r.opcoes,'observacao_alinhamento')
    info=[info sprintf('\n\n%s',r.opcoes.observacao_alinhamento)];
end
% Edit multiline permite rolar detalhes em telas menores e copiar os nomes.
uicontrol('Parent',panel,'Style','edit','Units','normalized','Position',[.05 .035 .90 .87], ...
    'String',info,'Min',0,'Max',2,'Enable','inactive','HorizontalAlignment','left', ...
    'FontName','Arial','FontSize',10,'ForegroundColor',tinta,'BackgroundColor','w', ...
    'TooltipString',sprintf('MAT: %s\nCSV: %s',r.arquivo_simulacao,r.arquivo_planta));
ax1=axes('Parent',f,'Units','normalized','Position',[.075 .455 .625 .245]);
a=plot(ax1,r.tempo,r.temp_real,'-','Color',azul,'LineWidth',1.8);hold(ax1,'on');
b=plot(ax1,r.tempo,r.temp_sim,'--','Color',laranja,'LineWidth',1.8);
c=plot(ax1,r.tempo,r.ref_real,'-.','Color',[.3 .3 .3],'LineWidth',1.1);
d=plot(ax1,r.tempo,r.ref_sim,':','Color',[.55 .36 .68],'LineWidth',1.4);
ylabel(ax1,'Temperatura (°C)');estiloEixo(ax1);
legend(ax1,[a b c d],{'Planta','Simulação','Ref. planta','Ref. simulação'}, ...
    'Location','northoutside','Orientation','horizontal','FontSize',9,'Box','off');
set(ax1,'Position',[.075 .455 .625 .245]);
ax2=axes('Parent',f,'Units','normalized','Position',[.075 .205 .625 .15]);
a=stairs(ax2,r.tempo,r.u_real,'-','Color',azul,'LineWidth',2);hold(ax2,'on');
b=stairs(ax2,r.tempo,r.u_sim,'--','Color',laranja,'LineWidth',1.5);
ylabel(ax2,'Controle (V)');xlabel(ax2,'Tempo relativo ao evento (s)');estiloEixo(ax2);
legend(ax2,[a b],{'Planta','Simulação'},'Location','northoutside', ...
    'Orientation','horizontal','FontSize',9,'Box','off');
set(ax2,'Position',[.075 .205 .625 .15]);
ymin=min([r.u_real(:);r.u_sim(:)]);ymax=max([r.u_real(:);r.u_sim(:)]);
margem=max(.15,.08*(ymax-ymin));ylim(ax2,[ymin-margem ymax+margem]);
linkaxes([ax1 ax2],'x');xlim(ax1,r.intervalo);
nota='';
if r.diferenca_referencia_max>.05
    nota=sprintf('ATENÇÃO: as referências diferem em até %.3f °C. Confira o alinhamento antes de interpretar as métricas.',r.diferenca_referencia_max);
    texto(f,[.04 .08 .93 .032],nota,10,[.65 .25 .06],fundo,'normal');
end
botao([.04 .027 .21 .045],'Diferença de temperatura',@diferenca);
botao([.265 .027 .20 .045],'Tabela de desempenho',@desempenho);
botao([.48 .027 .23 .045],'Salvar comparação (.mat)',@salvar);
botao([.73 .027 .24 .045],'Exportar gráficos (.png)',@exportar);
    function botao(pos,nome,acao)
        uicontrol('Parent',f,'Style','pushbutton','Units','normalized','Position',pos, ...
            'String',nome,'FontName','Arial','FontSize',10,'Callback',acao);
    end
    function desempenho(~,~)
        [d,ok]=compararDesempenho(r);
        if ok
            r.desempenho=d;
            mostrarDesempenho(d);
        end
    end
    function salvar(~,~)
        [n,p]=uiputfile(fullfile(pastaDadosComparacao,'comparacao_hvac.mat'),'Salvar dados, métricas e configuração');
        if isequal(n,0),return;end
        resultado=r;save(fullfile(p,n),'resultado','-v7');
    end
    function diferenca(~,~)
        g=figure('Name','Diferença | planta - simulação','NumberTitle','off','Color','w');
        ax=axes('Parent',g,'Position',[.11 .17 .83 .69]);
        plot(ax,r.tempo,r.erro,'Color',azul,'LineWidth',1.6);hold(ax,'on');
        plot(ax,r.intervalo,[0 0],'k--');estiloEixo(ax);xlim(ax,r.intervalo);
        xlabel(ax,'Tempo relativo ao evento (s)');ylabel(ax,'Temperatura real - simulada (°C)');
        title(ax,sprintf('Erro médio: %+.3f °C | RMSE: %.3f °C | Máximo absoluto: %.3f °C',r.vies,r.rmse,r.erro_max));
    end
    function exportar(~,~)
        [n,p]=uiputfile(fullfile(pastaDadosComparacao,'comparacao_hvac.png'),'Exportar figura para relatório');
        if isequal(n,0),return;end
        % Figura propria: nao exporta botoes nem um painel parcialmente rolado.
        g=figure('Visible','off','Color','w','Position',[30 30 1200 850]);
        limpeza=onCleanup(@() apagarFigura(g));
        a1=axes('Parent',g,'Position',[.09 .51 .86 .29]);
        plot(a1,r.tempo,r.temp_real,'-','Color',azul,'LineWidth',1.8);hold(a1,'on');
        plot(a1,r.tempo,r.temp_sim,'--','Color',laranja,'LineWidth',1.8);
        plot(a1,r.tempo,r.ref_real,'-.','Color',[.3 .3 .3]);
        plot(a1,r.tempo,r.ref_sim,':','Color',[.55 .36 .68],'LineWidth',1.4);
        ylabel(a1,'Temperatura (°C)');estiloEixo(a1);
        legend(a1,{'Planta','Simulação','Ref. planta','Ref. simulação'}, ...
            'Location','northoutside','Orientation','horizontal','Box','off');
        set(a1,'Position',[.09 .51 .86 .29]);xlim(a1,r.intervalo);
        a2=axes('Parent',g,'Position',[.09 .18 .86 .22]);
        stairs(a2,r.tempo,r.u_real,'-','Color',azul,'LineWidth',2);hold(a2,'on');
        stairs(a2,r.tempo,r.u_sim,'--','Color',laranja,'LineWidth',1.5);
        ylabel(a2,'Controle (V)');xlabel(a2,'Tempo relativo ao evento (s)');estiloEixo(a2);
        legend(a2,{'Planta','Simulação'},'Location','northoutside','Orientation','horizontal','Box','off');
        set(a2,'Position',[.09 .18 .86 .22]);xlim(a2,r.intervalo);ylim(a2,[ymin-margem ymax+margem]);
        annotation(g,'textbox',[.07 .89 .89 .09],'String', ...
            sprintf('SIMULAÇÃO E PLANTA\nRMSE: %.3f °C | MAE: %.3f °C | Máximo: %.3f °C | Erro médio: %+.3f °C',r.rmse,r.mae,r.erro_max,r.vies), ...
            'EdgeColor','none','FontSize',13,'FontWeight','bold','Interpreter','none');
        annotation(g,'textbox',[.07 .015 .89 .105],'String', ...
            {sprintf('Intervalo: %.2f a %.2f s | %d amostras | Offset: %+.3f °C',r.intervalo(1),r.intervalo(2),r.n_amostras,r.opcoes.offset_temperatura), ...
            ['MAT: ' ns es ' | CSV: ' nr er],nota}, ...
            'EdgeColor','none','FontSize',9,'Interpreter','none');
        set(g,'PaperPositionMode','auto');print(g,fullfile(p,n),'-dpng','-r180');
    end
end
function texto(pai,pos,s,tam,cor,fundo,peso)
uicontrol('Parent',pai,'Style','text','Units','normalized','Position',pos, ...
    'String',s,'FontName','Arial','FontSize',tam,'FontWeight',peso, ...
    'ForegroundColor',cor,'BackgroundColor',fundo,'HorizontalAlignment','left');
end
function estiloEixo(ax)
set(ax,'FontName','Arial','FontSize',10,'Box','off','TickDir','out', ...
    'XColor',[.35 .40 .45],'YColor',[.35 .40 .45],'GridLineStyle',':');
grid(ax,'on');
end
function apagarFigura(f)
if ishandle(f),delete(f);end
end

% Indicadores de seguimento da referencia sao distintos dos erros entre curvas.
function [d,ok]=compararDesempenho(r)
% Analisa automaticamente todo o intervalo comparado, sem formulario modal.
d=struct();ok=false;
sel=r.tempo>=r.intervalo(1) & r.tempo<=r.intervalo(2);
t=r.tempo(sel);
if numel(t)<3
    errordlg('O trecho precisa conter pelo menos três amostras.','Dados insuficientes');return;
end
cfg=struct('inicio_s',t(1),'fim_s',t(end),'faixa_C',0.5);
p=metricasEnsaio(t,r.temp_real(sel),r.ref_real(sel),cfg);
s=metricasEnsaio(t,r.temp_sim(sel),r.ref_sim(sel),cfg);
rotulos={'Referência final (°C)';'Tempo de subida 10–90% (s)'; ...
    'Pico de temperatura (°C)';'Instante do pico (s)'; ...
    'Sobressinal absoluto (°C)';'Sobressinal percentual (%)'; ...
    'Tempo de acomodação (s)'};
dados=[rotulos s.textos p.textos];
d=struct('configuracao',cfg,'simulacao',s,'planta',p,'tabela',{dados}, ...
    'arquivo_simulacao',r.arquivo_simulacao,'arquivo_planta',r.arquivo_planta, ...
    'intervalo_amostrado',[t(1) t(end)], ...
    'diferenca_referencia_max_C',max(abs(r.ref_real(sel)-r.ref_sim(sel))));
d.notas=sprintf(['Intervalo analisado: %.3f a %.3f s.\n' ...
    'Tempo de subida e sobressinal percentual usam a temperatura inicial do trecho e a referência final; requerem referência constante.\n' ...
    'Pico: máximo no aquecimento e mínimo no resfriamento; instante contado desde o início do trecho.\n' ...
    'Acomodação: entrada na faixa de ± %.3f °C, permanecendo nela até o fim do trecho analisado.\n' ...
    'Diferença máxima entre referências: %.3f °C.\nSIMULAÇÃO: %s\nPLANTA: %s'], ...
    t(1),t(end),cfg.faixa_C,d.diferenca_referencia_max_C,s.status,p.status);
ok=true;
end

% Calcula os indicadores no trecho selecionado. Subida e acomodacao exigem
% referencia constante; a faixa de acomodacao e definida pelo chamador.
function m=metricasEnsaio(t,y,ref,cfg)
t=t(:);y=y(:);ref=ref(:);
m=struct('referencia_final_C',ref(end),'subida_s',NaN,'pico_C',NaN, ...
    'instante_pico_s',NaN,'sobressinal_C',NaN,'sobressinal_pct',NaN, ...
    'acomodacao_s',NaN);
alvo=ref(end);
if y(1)<=alvo
    [m.pico_C,idxPico]=max(y);
    m.sobressinal_C=max(0,m.pico_C-alvo);
else
    [m.pico_C,idxPico]=min(y);
    m.sobressinal_C=max(0,alvo-m.pico_C);
end
m.instante_pico_s=t(idxPico)-cfg.inicio_s;
sub='N/A: referência variável';sob=sub;acom='Não atingido no trecho';
m.status='Patamar de referência constante.';
if max(ref)-min(ref)>1e-6
    sub='N/A: referência variável';sob=sub;acom=sub;
    m.status='A referência varia; os indicadores de degrau não se aplicam ao trecho completo.';
else
    ultimo=find(abs(y-ref)>cfg.faixa_C,1,'last');
    if isempty(ultimo),idx=1;else idx=ultimo+1;end
    if idx<=numel(t)
        m.acomodacao_s=t(idx)-cfg.inicio_s;acom=sprintf('%.3f',m.acomodacao_s);
        if idx==1,acom=[acom ' (já estava na faixa)'];end
    end
    delta=alvo-y(1);
    if abs(delta)>1e-6
        progresso=(y-y(1))/delta;
        m.sobressinal_pct=max(0,max(progresso)-1)*100;sob=sprintf('%.3f',m.sobressinal_pct);
        t10=cruzamento(t,progresso,.1);t90=cruzamento(t,progresso,.9);
        if isfinite(t10) && isfinite(t90)
            m.subida_s=t90-t10;sub=sprintf('%.3f',m.subida_s);
        else
            sub='90% não atingido';
        end
    else
        sub='N/A: temperatura inicial igual ao alvo';sob=sub;
    end
end
m.textos={sprintf('%.3f',m.referencia_final_C);sub;sprintf('%.3f',m.pico_C); ...
    sprintf('%.3f',m.instante_pico_s);sprintf('%.3f',m.sobressinal_C);sob;acom};
end

% Estima o primeiro cruzamento do nivel por interpolacao entre amostras.
function tc=cruzamento(t,y,nivel)
i=find(y>=nivel,1,'first');tc=NaN;
if isempty(i),return;end
if i==1,tc=t(1);return;end
tc=t(i-1)+(nivel-y(i-1))*(t(i)-t(i-1))/(y(i)-y(i-1));
end

function mostrarDesempenho(d)
f=figure('Name','Desempenho | Simulação × planta','NumberTitle','off', ...
    'Color',[.95 .97 .98],'Position',[80 70 700 340],'MenuBar','none','Resize','off');
movegui(f,'center');
texto(f,[.04 .89 .92 .07],'DESEMPENHO DO CONTROLADOR',17,[.12 .20 .29],[.95 .97 .98],'bold');
texto(f,[.04 .83 .92 .04],'Indicadores da resposta térmica: simulação e planta',10,[.12 .20 .29],[.95 .97 .98],'normal');
u=uitable('Parent',f,'Units','pixels','Position',[40 95 660 160], ...
    'Data',d.tabela,'ColumnName',{'Indicador','Simulação','Planta'}, ...
    'RowName',[],'ColumnWidth',{220 190 190},'ColumnEditable',[false false false], ...
    'FontName','Arial','FontSize',10);
% Dimensiona e centraliza a tabela conforme a extensao do conteudo.
drawnow;
ext=get(u,'Extent');
posFig=get(f,'Position');
largura=ext(3); altura=ext(4);
topo=255;
set(u,'Position',[round((posFig(3)-largura)/2) topo-altura largura altura]);
uicontrol('Parent',f,'Style','pushbutton','Units','pixels','Position',[160 35 190 28], ...
    'String','Salvar tabela (.csv)','Callback',@csv);
uicontrol('Parent',f,'Style','pushbutton','Units','pixels','Position',[390 35 190 28], ...
    'String','Salvar análise (.mat)','Callback',@mat);
    function csv(~,~)
        [n,p]=uiputfile(fullfile(pastaDadosComparacao,'desempenho_hvac.csv'),'Salvar tabela de desempenho');
        if isequal(n,0),return;end
        fid=fopen(fullfile(p,n),'w');
        if fid<0,errordlg('Não foi possível criar o CSV.');return;end
        limpeza=onCleanup(@() fclose(fid));
        fprintf(fid,'Indicador;Simulação;Planta\n');
        for k=1:size(d.tabela,1)
            fprintf(fid,'"%s";"%s";"%s"\n',d.tabela{k,1},d.tabela{k,2},d.tabela{k,3});
        end
        fprintf(fid,'\nCritérios e observações\n');
        linhas=regexp(d.notas,'\n','split');
        for k=1:numel(linhas),fprintf(fid,'"%s"\n',strrep(linhas{k},'"','""'));end
    end
    function mat(~,~)
        [n,p]=uiputfile(fullfile(pastaDadosComparacao,'desempenho_hvac.mat'),'Salvar indicadores e configuração');
        if isequal(n,0),return;end
        desempenho=d;save(fullfile(p,n),'desempenho','-v7');
    end
end

function pasta=pastaDadosComparacao
% Resolve dados/comparacoes a partir deste arquivo na raiz do projeto.
pasta=fullfile(fileparts(mfilename('fullpath')),'dados','comparacoes');
if ~exist(pasta,'dir'),mkdir(pasta);end
end