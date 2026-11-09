function configurar_pastas_simulink
% CONFIGURAR_PASTAS_SIMULINK Define os destinos de geracao e cache.
%
% Uso: configurar_pastas_simulink
% Resolve a raiz pela localizacao deste arquivo, adiciona as pastas do projeto
% ao path e configura codigo_gerado_simulink e cache_simulink.
% Se detectar artefatos de geracao na pasta atual, muda a pasta de trabalho
% para cache_simulink/pasta_trabalho. Nao remove os artefatos existentes.
% Compatibilidade: MATLAB/Simulink R2014a.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz
raiz=fileparts(mfilename('fullpath'));
addpath(raiz,'-begin');
addpath(fullfile(raiz,'base_controladores_simulink'),'-begin');
codigo=fullfile(raiz,'codigo_gerado_simulink');
cache=fullfile(raiz,'cache_simulink');
% Evita o erro de artefatos antigos na pasta atual sombrearem o destino.
conflito=exist(fullfile(pwd,'slprj'),'dir')~=0 || ...
    ~isempty(dir(fullfile(pwd,'*_ert_rtw'))) || ...
    ~isempty(dir(fullfile(pwd,'*_grt_rtw')));
if conflito
    trabalho=fullfile(cache,'pasta_trabalho');
    if ~exist(trabalho,'dir'), mkdir(trabalho); end
    cd(trabalho);
    fprintf('[SIMULINK] Pasta de trabalho: %s\n',trabalho);
end
% Atualiza a configuracao apenas quando os destinos diferem dos atuais.
cfg=Simulink.fileGenControl('getConfig');
if ~strcmp(cfg.CodeGenFolder,codigo) || ~strcmp(cfg.CacheFolder,cache)
    Simulink.fileGenControl('set','CodeGenFolder',codigo, ...
        'CacheFolder',cache,'createDir',true);
    fprintf('[SIMULINK] Codigo gerado em: %s\n',codigo);
end
end
