function importar_controlador(pastaOrigem, Ts)
% IMPORTAR_CONTROLADOR Integra o controlador gerado ao projeto embarcado.
%
% Uso: importar_controlador abre a selecao da pasta gerada pelo Simulink.
%      importar_controlador(pastaOrigem, Ts) informa a pasta e o periodo.
% Ts assume 0.2 s; esta implementacao aceita somente esse periodo nominal.
%
% Requer codigo C de taxa unica, interface nao reutilizavel com step(void),
% entradas Referencia/Temperatura e saida U. Parametros ajustaveis devem ser
% cadastrados com parametro_ajustavel e exportados nas fontes geradas.
%
% Atualiza src/gerado, src/modelo_selecionado.h, src/parametros_modelo.h
% e perfil_controlador.txt na raiz. A recuperacao da versao anterior e
% temporaria; uma importacao concluida nao preserva historico de modelos.
% Apos importar, compile e grave o firmware e reabra a GUI.
% Compatibilidade: MATLAB R2014a.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz
raiz=fileparts(mfilename('fullpath'));
if nargin<1 || isempty(pastaOrigem)
    pastaPadrao=fullfile(raiz,'codigo_gerado_simulink');
    if ~exist(pastaPadrao,'dir'), mkdir(pastaPadrao); end
    pastaOrigem=uigetdir(pastaPadrao,'Selecione o controlador gerado: pasta _ert_rtw');
    if isequal(pastaOrigem,0), return; end
end
if nargin<2, Ts=0.2; end
if ~isscalar(Ts) || ~isfinite(Ts) || abs(Ts-0.2)>1e-9
    error('Esta plataforma executa em 0.2 s. Configure essa taxa no modelo.');
end
raiz=fileparts(mfilename('fullpath'));
% Localiza um unico controlador e confere a interface usada pela ponte.
cs=dir(fullfile(pastaOrigem,'*.c')); hs=dir(fullfile(pastaOrigem,'*.h'));
modelos={}; codigo=''; cabecalhos='';
for i=1:numel(cs)
    t=fileread(fullfile(pastaOrigem,cs(i).name)); codigo=[codigo t];
    nomes=regexp(t,'void\s+([A-Za-z][A-Za-z0-9_]*)_step\s*\(\s*void\s*\)','tokens');
    for j=1:numel(nomes), modelos{end+1}=nomes{j}{1}; end
end
if numel(modelos)~=1, error('Esperado um unico modelo com step(void).'); end
nome=modelos{1};
for i=1:numel(hs), cabecalhos=[cabecalhos fileread(fullfile(pastaOrigem,hs(i).name))]; end
h=fileread(fullfile(pastaOrigem,[nome '.h']));
for campo={'Referencia','Temperatura','U'}
    if isempty(regexp(h,['\<' campo{1} '\>'],'once')), error('Interface exige Referencia, Temperatura e U.'); end
end
if isempty(strfind(h,[nome '_initialize'])), error('initialize ausente.'); end
% Nao interpretar comentarios como declaracoes.
limpo=regexprep(cabecalhos,'/\*[\s\S]*?\*/','');
limpo=regexprep(limpo,'//[^\n\r]*','');
exports=regexp(limpo,'extern\s+(real_T|real32_T)\s+([A-Za-z][A-Za-z0-9_]*)\s*(\[\s*\d+\s*\])?\s*;','tokens');
% Mantem a verificacao dos nomes AJ_ usados por modelos anteriores.
legados=unique(regexp(limpo,'\<AJ_[A-Za-z][A-Za-z0-9_]*\>','match'));
registro=struct('nome',{},'valor',{},'minimo',{},'maximo',{});
arq=fullfile(raiz,'registro_parametros.mat');
if exist(arq,'file'), d=load(arq,'registro'); registro=d.registro; end
% O cadastro determina o que pode ser ajustado; globais nao cadastradas sao ignoradas.
% Registros de outros modelos ausentes deste cabecalho nao sao importados.
identificadores=unique(regexp(limpo,'\<[A-Za-z][A-Za-z0-9_]*\>','match'));
todos=union(intersect({registro.nome},identificadores),legados);
nomesExportados={}; mapa=struct('rotulo',{},'expressao',{},'minimo',{},'maximo',{},'inicial',{});
for i=1:numel(exports)
    e=exports{i}; n=e{2};
    if any(strcmp(nomesExportados,n)), continue; end
    k=find(strcmp({registro.nome},n),1);
    if isempty(k)
        if strncmp(n,'AJ_',3)
            error('Falta registro de %s. Execute parametro_ajustavel antes de gerar.',n);
        end
        continue;
    end
    nomesExportados{end+1}=n;
    r=registro(k); dimensao='';
    if numel(e)>=3, dimensao=e{3}; end
    if isempty(dimensao), quantidade=1; else quantidade=str2double(regexp(dimensao,'\d+','match','once')); end
    if quantidade~=numel(r.valor), error('Dimensao de %s difere do registro. Regenere o modelo.',n); end
    % Nao aceitar parametro somente declarado/importado.
    padrao=['\<' n '\>\s*(\[\s*\d*\s*\])?\s*='];
    if isempty(regexp(codigo,padrao,'once')), error('%s sem definicao inicializada nas fontes.',n); end
    % Cada elemento de vetor recebe um indice ajustavel no pacote.
    for j=1:quantidade
        if isempty(dimensao), exp=n; rotulo=n; else exp=sprintf('%s[%d]',n,j-1); rotulo=sprintf('%s(%d)',n,j); end
        mapa(end+1)=struct('rotulo',rotulo,'expressao',exp,'minimo',r.minimo(j),'maximo',r.maximo(j),'inicial',r.valor(j));
    end
end
if ~isempty(setdiff(todos,nomesExportados))
    error('Parametro cadastrado/legado nao suportado: use extern real_T/real32_T escalar ou vetor fixo, sem const.');
end
if numel(mapa)>16, error('Maximo: 16 valores ajustaveis no Nano.'); end
% Confere as dependencias locais antes de substituir arquivos do projeto.
arquivos=[cs;hs];
for i=1:numel(arquivos)
    if any(strcmp(arquivos(i).name,{'ert_main.c','rt_main.c'})), continue; end
    t=fileread(fullfile(pastaOrigem,arquivos(i).name));
    inc=regexp(t,'#\s*include\s*"([^"]+)"','tokens');
    for j=1:numel(inc)
        if ~exist(fullfile(pastaOrigem,inc{j}{1}),'file'), error('Dependencia ausente: %s',inc{j}{1}); end
    end
end
% Identidade inclui fontes, cabecalhos, ordem/limites dos parametros e periodo.
assinatura=[codigo cabecalhos sprintf('%.9g',Ts)];
for i=1:numel(mapa), assinatura=[assinatura mapa(i).rotulo sprintf('%.9g,%.9g',mapa(i).minimo,mapa(i).maximo)]; end
md=java.security.MessageDigest.getInstance('SHA-256');
md.update(uint8(assinatura));
digest=typecast(md.digest(),'uint8');
id=lower(reshape(dec2hex(digest,2).',1,[])); id=id(1:16);
% Preparar todos os artefatos antes de substituir a importacao anterior.
stage=tempname; mkdir(stage); mkdir(fullfile(stage,'gerado'));
limpeza=onCleanup(@() limpar(stage));
for i=1:numel(arquivos)
    if any(strcmp(arquivos(i).name,{'ert_main.c','rt_main.c'})), continue; end
    copyfile(fullfile(pastaOrigem,arquivos(i).name),fullfile(stage,'gerado',arquivos(i).name));
end
% Gera o mapeamento da ponte sem alterar o codigo C produzido pelo Simulink.
t=sprintf(['#pragma once\nextern "C" {\n#include "gerado/%s.h"\n}\n' ...
    '#define MODELO_INICIAR %s_initialize\n#define MODELO_PASSO %s_step\n' ...
    '#define MODELO_ENTRADAS %s_U\n#define MODELO_SAIDAS %s_Y\n#define MODELO_PERIODO_S %.9ef\n'],nome,nome,nome,nome,nome,Ts);
escrever(fullfile(stage,'modelo_selecionado.h'),t);
t=sprintf('#pragma once\n#include "modelo_selecionado.h"\n#define PACOTE_ID "%s"\n#define PARAM_COUNT %d\n',id,numel(mapa));
t=[t sprintf('inline float parametroLer(unsigned char i) { switch(i) {\n')];
for i=1:numel(mapa), t=[t sprintf('case %d: return (float)%s;\n',i-1,mapa(i).expressao)]; end
t=[t sprintf('default: return 0; } }\ninline bool parametroValido(unsigned char i,float v) { switch(i) {\n')];
for i=1:numel(mapa), t=[t sprintf('case %d: return v>=%.9ef && v<=%.9ef;\n',i-1,mapa(i).minimo,mapa(i).maximo)]; end
t=[t sprintf('default: return false; } }\ninline void parametroEscrever(unsigned char i,float v) { switch(i) {\n')];
for i=1:numel(mapa), t=[t sprintf('case %d: %s=v; break;\n',i-1,mapa(i).expressao)]; end
t=[t sprintf('default: break; } }\n')];
escrever(fullfile(stage,'parametros_modelo.h'),t);
% O perfil informa a GUI sobre a identidade, os nomes e as faixas do pacote.
t=sprintf('%s\t%s\t%.9g\n',id,nome,Ts);
for i=1:numel(mapa), t=[t sprintf('%s\t%.9g\t%.9g\n',mapa(i).rotulo,mapa(i).minimo,mapa(i).maximo)]; end
escrever(fullfile(stage,'perfil_controlador.txt'),t);
% Copia de recuperacao apenas durante a troca, na pasta temporaria do sistema.
% Nao acumula controladores antigos dentro do projeto.
backup=tempname; mkdir(backup);
alvos={'gerado','modelo_selecionado.h','parametros_modelo.h','perfil_controlador.txt'};
try
    for i=1:numel(alvos)
        alvo=destino(raiz,alvos{i});
        if exist(alvo,'file') || exist(alvo,'dir')
            copyfile(alvo,fullfile(backup,alvos{i}));
        end
    end
catch err
    % Os destinos ainda nao foram modificados.
    limpar(backup);
    rethrow(err);
end
% Se a substituicao falhar, tenta restaurar todos os destinos anteriores.
try
    for i=1:numel(alvos)
        alvo=destino(raiz,alvos{i}); apagar(alvo);
        copyfile(fullfile(stage,alvos{i}),alvo);
    end
catch err
    restaurou=true;
    for i=1:numel(alvos)
        try
            alvo=destino(raiz,alvos{i}); apagar(alvo);
            antigo=fullfile(backup,alvos{i});
            if exist(antigo,'file') || exist(antigo,'dir'), copyfile(antigo,alvo); end
        catch falhaRestauro
            restaurou=false;
            warning('HVAC:restauro','Falha ao restaurar %s: %s',alvos{i},falhaRestauro.message);
        end
    end
    if restaurou
        limpar(backup);
    else
        % Excecao: preserva a unica copia de recuperacao se o restauro falhar.
        warning('HVAC:recuperacao','Restauro incompleto. Nao compile. Copia de recuperacao em: %s',backup);
    end
    rethrow(err);
end
limpar(backup);
fprintf('\nImportado: %s | ID: %s | Ts: %.3f s\n',nome,id,Ts);
fprintf('Fontes importadas para: %s\n',fullfile(raiz,'src','gerado'));
fprintf('Importacao concluida sem manter historico de controladores.\nCompile e grave antes de conectar a GUI.\n');
for i=1:numel(mapa), fprintf('%d: %s | [%g, %g] | PAR,%d,<valor>\n',i,mapa(i).rotulo,mapa(i).minimo,mapa(i).maximo,i); end
if isempty(mapa), fprintf('Sem parametros cadastrados e exportados: controlador de valores fixos.\n'); end
fprintf('Na GUI: abra Parametros Simulink, selecione o nome e aplique o valor. PAR e LISTAR continuam disponiveis.\n');
end
% O perfil fica na raiz; os arquivos compilados ficam em src.
function p=destino(raiz,n)
if strcmp(n,'perfil_controlador.txt'), p=fullfile(raiz,n); else p=fullfile(raiz,'src',n); end
end
function escrever(p,t)
f=fopen(p,'w'); if f<0, error('Nao foi possivel escrever %s',p); end
c=onCleanup(@() fclose(f)); fprintf(f,'%s',t);
end
function apagar(p)
if exist(p,'dir'), rmdir(p,'s'); elseif exist(p,'file'), delete(p); end
end
function limpar(p)
% Uma falha de limpeza nao deve ocultar o resultado da importacao/restauracao.
if exist(p,'dir')
    try
        rmdir(p,'s');
    catch err
        warning('HVAC:limpeza','Nao foi possivel remover a pasta temporaria %s: %s',p,err.message);
    end
end
end
