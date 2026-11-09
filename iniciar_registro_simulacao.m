function iniciar_registro_simulacao(modelo)
% INICIAR_REGISTRO_SIMULACAO Captura o contexto no inicio da simulacao.
%
% Uso no StartFcn: iniciar_registro_simulacao(bdroot)
% Sem argumento, utiliza o modelo principal atual.
% Limpa os sinais da execucao anterior e guarda identificacao do modelo,
% configuracao temporal e parametros disponiveis para a exportacao no StopFcn.
% Nao altera ganhos, estados iniciais nem a dinamica do modelo.
%
% Consulta registro_parametros.mat na raiz do projeto e captura os valores
% atuais dos parametros cadastrados disponiveis no Workspace.
% O cooler nao e capturado automaticamente.
% Preserve tambem o modelo e os valores utilizados no ensaio.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz

if nargin<1, modelo=bdroot; end

% Invalida dados anteriores antes de qualquer operacao que possa falhar.
chave=['HVAC_SIM_' modelo];
if isappdata(0,chave), rmappdata(0,chave); end
evalin('base','clear ref_sim temp_sim u_sim');

ctx=struct('modelo',modelo,'arquivo_modelo',get_param(modelo,'FileName'), ...
    'inicio_execucao',datestr(now,30), ...
    'tempo_inicial_configurado',get_param(modelo,'StartTime'), ...
    'tempo_final_configurado',get_param(modelo,'StopTime'), ...
    'solver',get_param(modelo,'Solver'), ...
    'passo_configurado',get_param(modelo,'FixedStep'), ...
    'unidade_temperatura','definir na comparacao: absoluta ou variacao', ...
    'cooler','nao registrado automaticamente', ...
    'parametros_cadastrados',struct('nome',{},'valor',{}));

ctx.configuracao=struct('versao',1,'TsRegistro',0.2);

% Procura o cadastro na raiz do projeto, onde parametro_ajustavel o salva.
raiz=fileparts(mfilename('fullpath'));
arq=fullfile(raiz,'registro_parametros.mat');

if exist(arq,'file')
    d=load(arq,'registro');
    if isfield(d,'registro')
        for k=1:numel(d.registro)
            n=d.registro(k).nome;
            if ~isvarname(n) || ...
                    ~evalin('base',sprintf('exist(''%s'',''var'')',n))
                continue;
            end

            % Captura o valor atual do Workspace.
            v=evalin('base',n);
            if isa(v,'Simulink.Parameter'), v=v.Value; end

            if isnumeric(v)
                ctx.parametros_cadastrados(end+1)=struct('nome',n,'valor',v);
            end
        end
    end
end

ctx.observacao_parametros=[ ...
    'Snapshot dos nomes cadastrados disponiveis; ' ...
    'pode incluir variaveis nao usadas neste modelo.'];

% Contexto temporario por modelo, recuperado pela rotina de exportacao.
setappdata(0,chave,ctx);
end