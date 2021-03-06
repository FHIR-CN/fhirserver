unit TerminologyServices;

interface

uses
  SysUtils, Classes,
  StringSupport,
  AdvObjects, AdvStringLists,
  FHIRTypes, FHIRComponents, FHIRResources,
  YuStemmer;

Type
  TFhirFilterOperator = FHIRTypes.TFhirFilterOperator;

  TCodeSystemProviderContext = class (TAdvObject)
  public
    function Link : TCodeSystemProviderContext; overload;
  end;

  TCodeSystemProviderFilterContext = class (TAdvObject)
  public
    function Link : TCodeSystemProviderFilterContext; overload;
  end;

  TCodeSystemProviderFilterPreparationContext = class (TAdvObject)
  public
    function Link : TCodeSystemProviderFilterPreparationContext; overload;
  end;

  TSearchFilterText = class (TAdvObject)
  private
    FFilter: string;
    FStems : TStringList;
    FStemmer : TYuStemmer_8;

    function find(s : String) : boolean;

    procedure process;
  public
    constructor Create(filter : String);  overload;
    destructor Destroy; override;

    function Link : TSearchFilterText; overload;

    function null : Boolean;
    function passes(value : String) : boolean; overload;
    function passes(stems : TAdvStringList; all : boolean) : boolean; overload;
    property filter : string read FFilter;
    property stems : TStringList read FStems;
  end;

  TCodeSystemProvider = {abstract} class (TAdvObject)
  public
    function Link : TCodeSystemProvider; overload;

    function TotalCount : integer;  virtual; abstract;
    function ChildCount(context : TCodeSystemProviderContext) : integer; virtual; abstract;
    function getcontext(context : TCodeSystemProviderContext; ndx : integer) : TCodeSystemProviderContext; virtual; abstract;
    function system(context : TCodeSystemProviderContext) : String; virtual; abstract;
    function getDisplay(code : String):String; virtual; abstract;
    function getDefinition(code : String):String; virtual; abstract;
    function locate(code : String) : TCodeSystemProviderContext; virtual; abstract;
    function locateIsA(code, parent : String) : TCodeSystemProviderContext; virtual; abstract;
    function IsAbstract(context : TCodeSystemProviderContext) : boolean; virtual; abstract;
    function Code(context : TCodeSystemProviderContext) : string; virtual; abstract;
    function Display(context : TCodeSystemProviderContext) : string; virtual; abstract;
    function Definition(context : TCodeSystemProviderContext) : string; virtual; abstract;
    procedure Displays(context : TCodeSystemProviderContext; list : TStringList); overload; virtual; abstract;
    procedure Displays(code : String; list : TStringList); overload; virtual; abstract;
    function doesFilter(prop : String; op : TFhirFilterOperator; value : String) : boolean; virtual;

    function getPrepContext : TCodeSystemProviderFilterPreparationContext; virtual;
    function searchFilter(filter : TSearchFilterText; prep : TCodeSystemProviderFilterPreparationContext) : TCodeSystemProviderFilterContext; virtual; abstract;
    function filter(prop : String; op : TFhirFilterOperator; value : String; prep : TCodeSystemProviderFilterPreparationContext) : TCodeSystemProviderFilterContext; virtual; abstract;
    function prepare(prep : TCodeSystemProviderFilterPreparationContext) : boolean; virtual; // true if the underlying provider collapsed multiple filters
    function filterLocate(ctxt : TCodeSystemProviderFilterContext; code : String) : TCodeSystemProviderContext; virtual; abstract;
    function FilterMore(ctxt : TCodeSystemProviderFilterContext) : boolean; virtual; abstract;
    function FilterConcept(ctxt : TCodeSystemProviderFilterContext): TCodeSystemProviderContext; virtual; abstract;
    function InFilter(ctxt : TCodeSystemProviderFilterContext; concept : TCodeSystemProviderContext) : Boolean; virtual; abstract;
    function isNotClosed(textFilter : TSearchFilterText; propFilter : TCodeSystemProviderFilterContext = nil) : boolean; virtual; abstract;

    procedure Close(ctxt : TCodeSystemProviderFilterPreparationContext); overload; virtual;
    procedure Close(ctxt : TCodeSystemProviderFilterContext); overload; virtual; abstract;
    procedure Close(ctxt : TCodeSystemProviderContext); overload; virtual; abstract;
  end;

implementation

{ TCodeSystemProvider }

procedure TCodeSystemProvider.Close(ctxt: TCodeSystemProviderFilterPreparationContext);
begin
  // do nothing
end;

function TCodeSystemProvider.doesFilter(prop: String; op: TFhirFilterOperator; value: String): boolean;
var
  ctxt : TCodeSystemProviderFilterContext;
begin
  ctxt := filter(prop, op, value, nil);
  result := ctxt <> nil;
  if result then
    Close(ctxt);
end;


function TCodeSystemProvider.getPrepContext: TCodeSystemProviderFilterPreparationContext;
begin
  result := nil;
end;

function TCodeSystemProvider.Link: TCodeSystemProvider;
begin
  result := TCodeSystemProvider(inherited link);
end;

function TCodeSystemProvider.prepare(prep : TCodeSystemProviderFilterPreparationContext) : boolean;
begin
  result := false;
end;

{ TSearchFilterText }

constructor TSearchFilterText.create(filter: String);
begin
  Create;
  FStemmer := GetStemmer_8('english');
  FStems := TStringList.Create;
  FFilter := filter;
  process;
end;

destructor TSearchFilterText.destroy;
begin
  FStems.Free;
  FStemmer.Free;
  inherited;
end;

function TSearchFilterText.find(s: String): boolean;
var
  L, H, I, C: Integer;
begin
  Result := False;
  L := 0;
  H := FStems.Count - 1;
  while not result and (L <= H) do
  begin
    I := (L + H) shr 1;
    C := CompareStr(FStems[I], copy(S, 1, length(FStems[i])));
    if C = 0 then
      Result := True
    else if C < 0 then
      L := I + 1
    else
      H := I - 1;
  end;
end;

function TSearchFilterText.Link: TSearchFilterText;
begin
  result := TSearchFilterText(inherited link);
end;

function TSearchFilterText.null: Boolean;
begin
  result := FStems.Count = 0;
end;

function TSearchFilterText.passes(value: String): boolean;
var
  i, j : integer;
begin
  result := Null;
  i := 1;
  while (not result) and (i <= length(value)) Do
  begin
    if CharInSet(value[i], ['0'..'9', 'a'..'z', 'A'..'Z']) then
    begin
      j := i;
      while (i <= length(value)) and CharInSet(value[i], ['0'..'9', 'a'..'z', 'A'..'Z']) do
        inc(i);
      result := find(lowercase(FStemmer.calc(copy(value, j, i-j))));
    end
    else
      inc(i);
  End;
end;

function TSearchFilterText.passes(stems: TAdvStringList; all : boolean): boolean;
var
  i : integer;
begin
  result := Null;
  if FStems.Count > 0 then
  begin
    if all then
    begin
      result := true;
      for i := 0 to stems.count - 1 do
        result := result and find(stems[i]);
    end
    else
      for i := 0 to stems.count - 1 do
        result := result or find(stems[i]);
  end;
end;

procedure TSearchFilterText.process;
var
  i, j : Integer;
begin
  i := 1;
  while i <= length(FFilter) Do
  begin
    if CharInSet(FFilter[i], ['0'..'9', 'a'..'z', 'A'..'Z']) then
    begin
      j := i;
      while (i <= length(FFilter)) and CharInSet(FFilter[i], ['0'..'9', 'a'..'z', 'A'..'Z']) do
        inc(i);
      FStems.Add(lowercase(FStemmer.calc(copy(FFilter, j, i-j))));
    end
    else
      inc(i);
  End;
  FStems.Sort;
end;

{ TCodeSystemProviderContext }

function TCodeSystemProviderContext.Link: TCodeSystemProviderContext;
begin
  result := TCodeSystemProviderContext(inherited link);
end;

{ TCodeSystemProviderFilterContext }

function TCodeSystemProviderFilterContext.Link: TCodeSystemProviderFilterContext;
begin
  result := TCodeSystemProviderFilterContext(inherited link);
end;

{ TCodeSystemProviderFilterPreparationContext }

function TCodeSystemProviderFilterPreparationContext.Link: TCodeSystemProviderFilterPreparationContext;
begin
  result := TCodeSystemProviderFilterPreparationContext(inherited Link);
end;

end.
