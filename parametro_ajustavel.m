function parametro_ajustavel(nome, valor, minimo, maximo)
% PARAMETRO_AJUSTAVEL Prepara um parametro para geracao e ajuste pela GUI.
%
% Uso: parametro_ajustavel(nome, valor, minimo, maximo)
% Exemplo: parametro_ajustavel('P', 3, 0, 10)
%
% nome: identificador do parametro, igual ao usado no campo do bloco Simulink.
% valor: escalar ou vetor numerico real e finito.
% minimo/maximo: limites escalares ou com as mesmas dimensoes de valor.
%
% Cria um Simulink.Parameter ExportedGlobal no Workspace base e salva seu
% cadastro em registro_parametros.mat, ao lado desta funcao na raiz do projeto.
% Repetir o mesmo nome atualiza seu cadastro. O prefixo AJ_ e opcional.
% O importador confere o limite total de 16 valores ajustaveis por pacote.
% Execute antes de gerar e ao preparar os valores de uma nova simulacao.
% Esta funcao nao envia valores ao Arduino nem grava o firmware.
%
% Autor: Thiago Miorando Tavolara
% TCC em Engenharia de Controle e Automacao - UFRGS
% Orientacao: Prof. Marcelo Gotz
if ~ischar(nome) || size(nome,1)~=1 || ~isvarname(nome) || isempty(regexp(nome,'^[A-Za-z][A-Za-z0-9_]*$','once'))
    error('Use um identificador valido, como Kp, Ki ou Ganho.');
end
% Evita nomes validos no MATLAB que colidiriam com palavras de C/C++.
reservados={'auto','bool','break','case','catch','char','class','const', ...
    'continue','default','delete','do','double','else','enum','extern', ...
    'false','float','for','friend','goto','if','inline','int','long', ...
    'namespace','new','operator','private','protected','public','register', ...
    'return','short','signed','sizeof','static','struct','switch','template', ...
    'this','throw','true','try','typedef','typename','union','unsigned', ...
    'using','virtual','void','volatile','while','nullptr','constexpr', ...
    'restrict','static_cast','dynamic_cast','const_cast','reinterpret_cast', ...
    'typeid','wchar_t','mutable','explicit','export','and','or','not', ...
    'xor','bitand','bitor','compl','and_eq','or_eq','xor_eq','not_eq'};
if any(strcmp(nome,reservados)), error('Nome reservado em C/C++. Escolha outro nome.'); end
if ~isnumeric(valor) || ~isreal(valor) || isempty(valor) || ~isvector(valor) || any(~isfinite(valor(:)))
    error('Valor deve ser um escalar/vetor numerico real e finito.');
end
if numel(valor)>16, error('Limite de 16 elementos por pacote.'); end
% Limites escalares sao repetidos para todos os elementos do vetor.
if isscalar(minimo), minimo=repmat(minimo,size(valor)); end
if isscalar(maximo), maximo=repmat(maximo,size(valor)); end
if ~isequal(size(valor),size(minimo)) || ~isequal(size(valor),size(maximo)) || any(~isfinite(minimo(:))) || any(~isfinite(maximo(:))) || any(minimo(:)>maximo(:)) || any(valor(:)<minimo(:)) || any(valor(:)>maximo(:)) || any(abs([minimo(:);maximo(:)])>double(realmax('single')))
    error('Limites devem ser escalares ou ter o tamanho do valor, em faixa float32.');
end
% ExportedGlobal permite localizar e atualizar a variavel no codigo gerado.
p=Simulink.Parameter;
p.Value=double(valor);
p.DataType='double';
% R2014a pode expor a classe de armazenamento pela propriedade RTWInfo.
try
    p.CoderInfo.StorageClass='ExportedGlobal';
catch
    p.RTWInfo.StorageClass='ExportedGlobal';
end
% O bloco usa o objeto do Workspace; o importador consulta o cadastro em MAT.
assignin('base',nome,p);
raiz=fileparts(mfilename('fullpath'));
arquivo=fullfile(raiz,'registro_parametros.mat');
registro=struct('nome',{},'valor',{},'minimo',{},'maximo',{});
if exist(arquivo,'file'), dados=load(arquivo,'registro'); registro=dados.registro; end
% Atualiza o registro existente ou acrescenta um novo nome ao cadastro.
k=find(strcmp({registro.nome},nome),1);
if isempty(k), k=numel(registro)+1; end
registro(k)=struct('nome',nome,'valor',double(valor),'minimo',minimo,'maximo',maximo);
save(arquivo,'registro');
fprintf('%s preparado. Use esse nome no parametro do bloco e gere o subsistema.\n',nome);
end
