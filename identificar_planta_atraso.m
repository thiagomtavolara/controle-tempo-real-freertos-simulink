function resultado=identificar_planta_atraso
% IDENTIFICAR_PLANTA_ATRASO Estima o modelo termico a partir de ensaios abertos.
%
% Uso: resultado = identificar_planta_atraso
% Selecione um ou mais CSVs em dados/ensaios. Requer MATLAB R2014a e
% Optimization Toolbox para executar o ajuste com lsqnonlin.
%
% Modelo: G(s) = exp(-L*s) * sum(Ki/(taui*s + 1)), i = 1..3.
% A entrada e o comando nominal da lampada, em V; a saida e a variacao de
% temperatura, em C, em relacao a media do trecho anterior a excitacao.
% Considera entrada constante entre registros e estados incrementais nulos.
% Estima ganhos/constantes de tempo positivos e um atraso comum de 0 a 1 s.
%
% Os CSVs devem iniciar com timestamp,modo,setpoint,temperatura,controle.
% Timestamp em ms, estritamente crescente; manter um trecho inicial com
% comando zero e ao menos duas amostras antes da primeira excitacao positiva.
%
% Retorna um unico modelo em resultado.modelos, dados e arquivos utilizados.
% Salva MAT, parametros TXT e graficos em dados/identificacoes, em uma pasta
% resultado_identificao_AAAAMMDD_HHMMSS. O RMSE dos dados usados no ajuste
% mede concordancia com esses ensaios; nao e uma validacao independente.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz
pastaEnsaios=fullfile(fileparts(mfilename('fullpath')),'dados','ensaios');
if ~exist(pastaEnsaios,'dir'), mkdir(pastaEnsaios); end
[arquivos,pastaSelecionada]=uigetfile(fullfile(pastaEnsaios,'*.csv'), ...
 'Selecione um ou mais ensaios em malha aberta (Ctrl+clique)', 'MultiSelect','on');
if isequal(arquivos,0), error('Selecao cancelada.'); end
if ischar(arquivos), arquivos={arquivos}; end
N=numel(arquivos); D=cell(1,N); passos=zeros(1,N);
for j=1:N
 D{j}=ler(fullfile(pastaSelecionada,arquivos{j}));
 % Subamostragem no ajuste para limitar custo computacional.
 % Usa uma amostra a cada 2 no multinivel original e a cada 5 nos demais.
 % A regra depende do nome do arquivo; revisar ao adaptar para outra campanha.
 if strcmpi(arquivos{j},'identificacao_multinivel_02.csv')
  passos(j)=2;
 else
  passos(j)=5;
 end
end
fprintf('Identificacao conjunta com %d ensaio(s).\n',N);
op=optimset('Display','off','MaxIter',160,'MaxFunEvals',3000,'TolFun',1e-8,'TolX',1e-8);
% Parametrizacao logaritmica mantem K e tau positivos durante a otimizacao.
% Faixas: K de 1e-4 a 100; tau de 0.05 a 10000 s.
lo=[log(1e-4)*ones(1,3),log(.05)*ones(1,3)];
hi=[log(100)*ones(1,3),log(10000)*ones(1,3)];
% Repete o ajuste com tres valores iniciais de L e seleciona o menor custo.
% Os ganhos e constantes de tempo usam os mesmos palpites nas tres tentativas.
inicios=[.05 .2 .5]; melhor=Inf; tentativas=struct([]);
for inicio=inicios
 p0=[log([.7 4.5 19 2.5 29 820]),inicio];
 lb=[lo 0]; ub=[hi 1];
 fprintf('Ajustando modelo com atraso, L inicial %.2f s...\n',inicio);
 [p,custo,~,flag,saida]=lsqnonlin(@(x)residuos(x,D,passos),p0,lb,ub,op);
 tentativa=struct('inicio',inicio,'p',p,'custo',custo,'exitflag',flag,'output',saida);
 if isempty(tentativas), tentativas=tentativa; else tentativas(end+1)=tentativa; end
 if custo<melhor, melhor=custo; vencedor=tentativa; end
end
p=vencedor.p;
m=struct(); m.K=exp(p(1:3)); m.tau=exp(p(4:6)); m.L=p(7);
m.p=p; m.custo=melhor; m.exitflag=vencedor.exitflag; m.tentativas=tentativas;
m.RMSE=zeros(1,N); m.MAE=zeros(1,N); m.previsao=cell(1,N);
% Calcula previsoes e metricas com todas as amostras, sem subamostragem.
for j=1:N
 yp=prever(p,D{j},1)+D{j}.T0; e=D{j}.y-yp;
 m.previsao{j}=yp; m.RMSE(j)=sqrt(mean(e.^2)); m.MAE(j)=mean(abs(e));
end
modelos=m; % Campo mantido para compatibilidade com arquivos existentes.
fprintf('L=%.9g s | RMSE por ensaio:',m.L);
fprintf(' %.6f',m.RMSE); fprintf(' C\n');
if m.exitflag<=0, warning('Ajuste nao convergiu normalmente: confira tentativas.'); end
resultado=struct('modelos',modelos,'dados',{D},'passos_ajuste',passos, ...
 'arquivos',{arquivos},'descricao','Tres ramos positivos. Pesos iguais por ensaio; estados zero; sem validacao.');
pastaSaida=fullfile(fileparts(mfilename('fullpath')),'dados','identificacoes');
if ~exist(pastaSaida,'dir'), mkdir(pastaSaida); end
pasta=fullfile(pastaSaida,['resultado_identificao_' datestr(now,'yyyymmdd_HHMMSS')]);
% Em colisao de nome, usa uma pasta temporaria unica na pasta atual.
if exist(pasta,'dir'), pasta=tempname(pwd); end
mkdir(pasta); resultado.pasta=pasta;
% O nome interno do MAT permanece resultado_atraso.mat para compatibilidade.
save(fullfile(pasta,'resultado_atraso.mat'),'resultado','-v7');
fid=fopen(fullfile(pasta,'parametros.txt'),'w');
fprintf(fid,'MODELO COM ATRASO | exitflag=%d | custo=%.17g\n',m.exitflag,m.custo);
fprintf(fid,'K = [%.17g %.17g %.17g];\n',m.K);
fprintf(fid,'tau = [%.17g %.17g %.17g];\n',m.tau);
fprintf(fid,'L = %.17g;\n',m.L);
fprintf(fid,['G(s) = exp(-%.12g*s) * (%.12g/(%.12g*s+1) + ' ...
             '%.12g/(%.12g*s+1) + %.12g/(%.12g*s+1))\n'], ...
             m.L,m.K(1),m.tau(1),m.K(2),m.tau(2),m.K(3),m.tau(3));
fprintf(fid,'RMSE por ensaio (C):\n');
for j=1:N, fprintf(fid,'  %s: %.9g\n',arquivos{j},m.RMSE(j)); end
fclose(fid);
for j=1:N
 h=figure('Name',['Identificacao da planta - ' arquivos{j}],'Units','normalized','Position',[.1 .15 .8 .7]);
 subplot(3,1,1); plot(D{j}.t,D{j}.y,'k',D{j}.t,m.previsao{j},'r-');
 grid on; ylabel('Temperatura (C)'); legend('Medido','Modelo com atraso');
 subplot(3,1,2); plot(D{j}.t,D{j}.y-m.previsao{j},'r-');
 grid on; xlabel('Tempo (s)'); ylabel('Medido - previsto (C)');
 subplot(3,1,3); stairs(D{j}.t,comando_ensaio(D{j}),'k'); grid on; xlabel('Tempo (s)'); ylabel('Comando (V)');
 print(h,fullfile(pasta,sprintf('ajuste_%d.png',j)),'-dpng','-r150');
end
fprintf('Resultados: %s\n',pasta);
end
% Reconstroi o comando pela soma dos incrementos aplicados em cada evento.
function u=comando_ensaio(d)
 u=double(bsxfun(@ge,d.t,d.eventos'))*d.du;
end
% Le o CSV e determina a base termica e os degraus do comando registrado.
function d=ler(arquivo)
fid=fopen(arquivo,'r'); if fid<0, error('Nao foi possivel abrir CSV.'); end
cab=fgetl(fid); fclose(fid);
esperado={'timestamp','modo','setpoint','temperatura','controle'};
cols=strsplit(strtrim(cab),',');
if numel(cols)<5 || ~all(strcmp(cols(1:5),esperado)), error('Cabecalho CSV inesperado.'); end
a=dlmread(arquivo,',',1,0);
if size(a,2)<5 || any(any(~isfinite(a(:,1:5)))), error('CSV invalido.'); end
d.t=(a(:,1)-a(1,1))/1000; d.y=a(:,4); u=a(:,5);
if any(diff(d.t)<=0), error('Tempo deve ser estritamente crescente.'); end
on=find(u>0,1); if isempty(on), error('Nao ha excitacao.'); end
% Usa as amostras disponiveis nos 60 s anteriores a primeira excitacao.
% Essa media define a base; nao comprova equilibrio termico da planta.
pre=d.t<d.t(on) & d.t>=d.t(on)-60;
if sum(pre)<2 || any(u(pre)~=0), error('Falta trecho inicial com comando zero.'); end
if any(a(u>0,2)~=0), error('Use ensaios de identificacao em malha aberta.'); end
d.T0=mean(d.y(pre)); idx=[1; find(diff(u)~=0)+1];
d.eventos=d.t(idx); d.du=diff([0;u(idx)]); d.arquivo=arquivo;
end
% Divide cada residuo pela raiz do numero de pontos usados no ensaio.
% Assim, o custo soma erros quadraticos medios, sem favorecer ensaios longos.
function r=residuos(p,D,passos)
r=[];
for j=1:numel(D)
 ind=1:passos(j):numel(D{j}.t); yp=prever(p,D{j},passos(j));
 r=[r;(yp-(D{j}.y(ind)-D{j}.T0))/sqrt(numel(ind))]; %#ok<AGROW>
end
end
% Superpoe as respostas aos degraus, com atraso comum e estados iniciais nulos.
% A subamostragem reduz os instantes avaliados, preservando todos os eventos.
function yp=prever(p,d,passo)
K=exp(p(1:3)); tau=exp(p(4:6)); L=0; if numel(p)==7, L=p(7); end
t=d.t(1:passo:end); dt=max(bsxfun(@minus,t,d.eventos')-L,0); yp=zeros(size(t));
for i=1:3, yp=yp+K(i)*((-expm1(-dt/tau(i)))*d.du); end
end
