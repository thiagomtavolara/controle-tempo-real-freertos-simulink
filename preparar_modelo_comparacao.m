function preparar_modelo_comparacao(arquivo)
% PREPARAR_MODELO_COMPARACAO Configura os registros externos da simulacao.
%
% Uso: preparar_modelo_comparacao abre a selecao do modelo SLX completo.
%      preparar_modelo_comparacao(arquivo) utiliza o caminho informado.
% O modelo deve estar salvo e parado. A base ja preparada pode ser usada
% diretamente; repita esta rotina se recriar o modelo ou remover registros.
%
% Requer um subsistema no nivel principal com entradas Referencia/Temperatura
% e saida U, alem do bloco Planta com uma entrada. Registra referencia,
% temperatura realimentada e comando aplicado a planta a cada 0.2 s.
% Preserva o interior do controlador e cria uma copia do SLX antes da edicao.
% Configura StartFcn/StopFcn para capturar o contexto e exportar os sinais.
% As rotinas auxiliares precisam estar acessiveis no path do MATLAB.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz
if nargin<1
    [n,p]=uigetfile('*.slx','Selecione o modelo completo (controlador + planta)');
    if isequal(n,0), return; end
    arquivo=fullfile(p,n);
end
load_system(arquivo);
[~,modelo]=fileparts(arquivo);
if ~strcmp(get_param(modelo,'SimulationStatus'),'stopped')
    error('Pare a simulacao antes de preparar o modelo.');
end
if strcmp(get_param(modelo,'Dirty'),'on')
    error('Salve as alteracoes do modelo e execute novamente. Nada foi alterado.');
end
arquivo=get_param(modelo,'FileName');
pasta=fileparts(arquivo);
% Identifica o subsistema pelas portas, sem depender do nome do controlador.
subs=find_system(modelo,'SearchDepth',1,'BlockType','SubSystem');
candidatos={}; indices=[];
for k=1:numel(subs)
    ins=find_system(subs{k},'SearchDepth',1,'BlockType','Inport');
    outs=find_system(subs{k},'SearchDepth',1,'BlockType','Outport');
    if numel(ins)~=2 || numel(outs)~=1, continue; end
    ni=get_param(ins,'Name'); no=get_param(outs{1},'Name');
    ir=find(strcmp(ni,'Referencia'),1); it=find(strcmp(ni,'Temperatura'),1);
    if ~isempty(ir) && ~isempty(it) && strcmp(no,'U')
        candidatos{end+1}=subs{k};
        indices(end+1,:)=[str2double(get_param(ins{ir},'Port')) str2double(get_param(ins{it},'Port'))];
    end
end
if numel(candidatos)~=1
    error('Esperado um unico subsistema com Referencia, Temperatura e U no nivel principal.');
end
controlador=candidatos{1}; ph=get_param(controlador,'PortHandles');
planta=[modelo '/Planta'];
try
    get_param(planta,'Handle');
catch
    error('Nomeie o bloco da planta no nivel principal como Planta.');
end
pp=get_param(planta,'PortHandles');
if numel(pp.Inport)~=1, error('O bloco Planta deve ter uma entrada.'); end
% Usa os sinais que chegam ao controlador e a planta, incluindo a temperatura
% realimentada; nao presume que a saida direta da planta seja absoluta.
portas=[ph.Inport(indices(1,1)) ph.Inport(indices(1,2)) pp.Inport(1)];
fontes=zeros(1,3);
for k=1:3
    l=get_param(portas(k),'Line');
    if l<0, error('Referencia, Temperatura e entrada da Planta devem estar conectadas.'); end
    fontes(k)=get_param(l,'SrcPortHandle');
    if fontes(k)<0, error('Nao foi possivel identificar a origem de um sinal.'); end
end
vars={'ref_sim','temp_sim','u_sim'};
existentes=cell(1,3);
for k=1:3
    encontrados=find_system(modelo,'BlockType','ToWorkspace','VariableName',vars{k});
    if numel(encontrados)>1, error('Mais de um To Workspace usa %s.',vars{k}); end
    if ~isempty(encontrados)
        if ~strcmp(get_param(encontrados{1},'Parent'),modelo)
            error('%s esta dentro de um subsistema. Mova o registro para o nivel principal.',vars{k});
        end
        existentes{k}=encontrados{1};
    end
end
% A copia de seguranca preserva o arquivo salvo antes de editar os registros.
backup=fullfile(pasta,[modelo '_antes_comparacao_' datestr(now,'yyyymmdd_HHMMSS') '.slx']);
if exist(backup,'file'), error('Backup ja existe. Aguarde um segundo e tente novamente.'); end
copyfile(arquivo,backup);
load_system('simulink');
try
    blocos=find_system(modelo,'SearchDepth',1,'Type','Block'); xmax=650;
    for k=1:numel(blocos)
        pos=get_param(blocos{k},'Position'); xmax=max(xmax,pos(3));
    end
    for k=1:3
        if isempty(existentes{k})
            destino=[modelo '/Registro_' vars{k}];
            novo=add_block('simulink/Sinks/To Workspace',destino, ...
                'MakeNameUnique','on','Position',[xmax+100 60+100*k xmax+230 100+100*k]);
            destino=getfullname(novo);
        else
            destino=existentes{k};
        end
        set_param(destino,'VariableName',vars{k},'SaveFormat','Structure With Time', ...
            'MaxDataPoints','inf','Decimation','1','SampleTime','0.2');
        dp=get_param(destino,'PortHandles'); linha=get_param(dp.Inport(1),'Line');
        if linha>=0
            if get_param(linha,'SrcPortHandle')==fontes(k), continue; end
            delete_line(linha);
        end
        add_line(modelo,fontes(k),dp.Inport(1),'autorouting','on');
    end
    % Os registros devem chegar ao workspace base ao usar Run na janela do modelo.
    set_param(modelo,'ReturnWorkspaceOutputs','off');
    % Acrescenta os comandos sem substituir o conteudo dos callbacks existentes.
    inserirCallback(modelo,'StartFcn','iniciar_registro_simulacao(bdroot);');
    inserirCallback(modelo,'StopFcn','exportar_simulacao_comparacao(bdroot);');
    save_system(modelo);
catch erro
    warning('HVAC:preparacao','Preparacao incompleta. Feche SEM salvar e restaure o backup: %s',backup);
    rethrow(erro);
end
open_system(modelo);
fprintf('Modelo preparado: %s\nBackup: %s\n',arquivo,backup);
fprintf('Mantenha as rotinas .m deste pacote na mesma pasta do modelo. Execute a simulacao pelo botao Run.\n');
end

% Evita inserir novamente o mesmo comando ao preparar um modelo ja configurado.
function inserirCallback(modelo,evento,comando)
antigo=get_param(modelo,evento);
if isempty(strfind(antigo,comando))
    set_param(modelo,evento,sprintf('%s\n%s',antigo,comando));
end
end
