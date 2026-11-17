function caminho=exportar_simulacao_comparacao(modelo)
% EXPORTAR_SIMULACAO_COMPARACAO Salva os sinais simulados em arquivo MAT.
%
% Uso no StopFcn: exportar_simulacao_comparacao(bdroot)
% Sem argumento, utiliza o modelo principal atual.
% Retorna o caminho salvo, ou texto vazio se a exportacao nao for concluida.
% Requer o contexto do StartFcn e ref_sim, temp_sim e u_sim no Workspace base,
% em Structure With Time, com sinais escalares finitos e ao menos duas amostras.
%
% Salva em dados/simulacoes, relativo a este arquivo na raiz do projeto.
% Preserva a base de tempo de cada sinal, sem reamostragem, e disponibiliza
% ultimo_arquivo_simulacao no Workspace. Uma simulacao interrompida tambem
% pode ser exportada; confira sua duracao antes de comparar com o ensaio.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz
caminho='';
if nargin<1, modelo=bdroot; end
try
    chave=['HVAC_SIM_' modelo];
    if ~isappdata(0,chave), error('Contexto ausente. Rode novamente pelo botao Run do modelo preparado.'); end
    meta=getappdata(0,chave);
    nomes={'ref_sim','temp_sim','u_sim'}; sinais=cell(1,3);
    for k=1:3
        if ~evalin('base',sprintf('exist(''%s'',''var'')',nomes{k}))
            error('Sinal %s ausente. Use Run e confira os blocos To Workspace.',nomes{k});
        end
        s=evalin('base',nomes{k});

        % Normaliza um sinal escalar salvo como matriz 1x1xN.
        % Somente converte quando existe um valor por instante.
        if isstruct(s) && isscalar(s) && ...
                isfield(s,'time') && isfield(s,'signals') && ...
                isstruct(s.signals) && numel(s.signals)==1 && ...
                isfield(s.signals,'values') && ...
                isnumeric(s.time) && isnumeric(s.signals.values) && ...
                numel(s.time)==numel(s.signals.values)
            s.time=s.time(:);
            s.signals.values=s.signals.values(:);
            s.signals.dimensions=1;
        end

        sinais{k}=s;
        if ~isstruct(s) || ~isfield(s,'time') || ~isfield(s,'signals') || ...
                numel(s.signals)~=1 || ~isfield(s.signals,'values') || ...
                ~isvector(s.signals.values) || numel(s.time)~=numel(s.signals.values) || numel(s.time)<2
            error('%s deve ser escalar, em Structure With Time, com ao menos duas amostras.',nomes{k});
        end
        if any(~isfinite(s.time(:))) || any(~isfinite(s.signals.values(:)))
            error('%s possui dados nao finitos; exportacao cancelada.',nomes{k});
        end
    end
    ref_sim=sinais{1}; temp_sim=sinais{2}; u_sim=sinais{3};
    meta.fim_execucao=datestr(now,30);
    % Limite comum aos tres registros; pode ser menor que o StopTime configurado.
    meta.ultimo_tempo_registrado=min([ref_sim.time(end),temp_sim.time(end),u_sim.time(end)]);
    meta.observacao_duracao='Pode conter uma simulacao interrompida. Confira ultimo_tempo_registrado e tempo_final_configurado.';
    ensaio_simulacao=struct('versao',1,'meta',meta,'ref',ref_sim,'temp',temp_sim,'u',u_sim);
    pasta=fullfile(fileparts(mfilename('fullpath')),'dados','simulacoes');
    if ~exist(pasta,'dir'), mkdir(pasta); end
    base=[modelo '_' datestr(now,'yyyymmdd_HHMMSS')];
    caminho=fullfile(pasta,[base '.mat']); k=1;
    % Evita sobrescrever arquivos de execucoes salvas no mesmo segundo.
    while exist(caminho,'file')
        caminho=fullfile(pasta,sprintf('%s_%02d.mat',base,k)); k=k+1;
    end
    % Mantem os sinais isolados e a estrutura consolidada para os leitores do projeto.
    save(caminho,'ensaio_simulacao','ref_sim','temp_sim','u_sim','-v7');
    assignin('base','ultimo_arquivo_simulacao',caminho);
    fprintf('[SIMULACAO SALVA] %s\n',caminho);
catch erro
    warning('HVAC:exportacao','Simulacao NAO exportada: %s',erro.message);
end
end
