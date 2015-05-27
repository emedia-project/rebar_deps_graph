%% -------------------------------------------------------------------
%%
%% Original file : mapdeps.erl
%% Copyright (c) 2013 Basho Technologies, Inc.
%%
%% Modifications : Grégoire Lejeune
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License. You may obtain
%% a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied. See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%
%% -------------------------------------------------------------------

-module(deps_graph_plugin).
-export(['graph-deps'/2]).

-define(ABORT(Str, Args), rebar_utils:abort(Str, Args)).
-define(PLUGIN_NODE, "rebar_deps_graph").

'graph-deps'(Config, _App) ->
  case rebar_utils:processing_base_dir(Config) of
    true ->
      {ok, CWD} = file:get_cwd(),
      map_dir(Config, CWD);
    false ->
      ok
  end.

map_dir(Config, BaseDir) ->
  RebarPath = filename:join([BaseDir, "rebar.config"]),
  case filelib:is_regular(RebarPath) of
    true ->
      Map = map_rebar(BaseDir, RebarPath, ordsets:new()),
      gen_graph(Config, Map);
    false ->
      ?ABORT("~p not found.", [RebarPath]),
      exit(-1)
  end.

gen_graph(Config, Map) ->
  IO = open_graph_file(Config),
  file_start(IO),
  [ file_edge(IO, From, To, Attrs) || {From, To, Attrs} <- Map ],
  file_end(IO),
  close_graph_file(IO).

open_graph_file(Config) ->
  case rebar_config:get_global(Config, graph, rebar_config:get_local(Config, deps_graph_file, undefined)) of
    undefined -> standard_io;
    Path -> case file:open(Path, [write]) of
        {ok, IO} -> IO;
        {error, _} -> standard_io
      end
  end.

close_graph_file(standard_io) -> ok;
close_graph_file(IO) -> file:close(IO).

%% Read a rebar file. Find any `deps' option. Accumulate tuples of the
%% form `{App, Dep}' for each element in this deps list.  Recurse and
%% attempt to read the rebar.config for each dep.
map_rebar(BaseDir, Path, Acc) ->
  case app_name(Path) of
    ?PLUGIN_NODE -> Acc;
    From ->
      case file:consult(Path) of
        {ok, Opts} ->
          Deps = proplists:get_value(deps, Opts, []),
          lists:foldl(
            fun
              ({DepName, _, _}, A) ->
                case atom_to_list(DepName) of
                  ?PLUGIN_NODE -> A;
                  To ->
                    case ordsets:is_element({To, From}, A) of
                      true ->
                        ordsets:add_element({From, To, [{color, red}]}, A);
                      false ->
                        NA = ordsets:add_element({From, To, []}, A),
                        DepPath = filename:join(
                                    [BaseDir, "deps",
                                     atom_to_list(DepName),
                                     "rebar.config"]),
                        map_rebar(BaseDir, DepPath, NA)
                    end
                end;
              ({DepName, _, _, _}, A) ->
                ordsets:add_element({From, atom_to_list(DepName), [{color, blue}]}, A)
            end,
            Acc,
            Deps);
        _ ->
          ordsets:add_element({From, [], []}, Acc)
      end
  end.

app_name(Path) ->
  %% assumes Path ends in rebar.config
  filename:basename(filename:dirname(Path)).

file_start(IO) ->
  io:format(IO, "digraph {~n", []),
  io:format(IO, "  rankdir=LR;~n", []),
  io:format(IO, "  remincross=true;~n", []),
  io:format(IO, "  node[shape=box];~n", []).

file_end(IO) ->
  io:format(IO, "}~n", []).

file_edge(IO, From, [], Attrs) ->
  MissingDepsNodeName = io_lib:format("missing_deps_for_~s", [From]),
  io:format(IO, "  ~s[shape=point];~n", [MissingDepsNodeName]),
  file_edge(IO, From, MissingDepsNodeName, Attrs);
file_edge(IO, From, To, Attrs) ->
  case Attrs of
    [] ->
      io:format(IO, "  ~s -> ~s;~n", [From, To]);
    Attrs ->
      StrAttrs = string:join(lists:foldl(fun({Key, Value}, Acc) ->
                Acc ++ [io_lib:format("~p=~p", [Key, Value])]
            end, [], Attrs), ";"),
      io:format(IO, "  ~s -> ~s[~s];~n", [From, To, StrAttrs])
  end.
