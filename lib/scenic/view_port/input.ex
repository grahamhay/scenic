#
#  Created by Boyd Multerer on 11/05/17.
#  Rewritten: 3/25/2018
#  Copyright © 2017 Kry10 Industries. All rights reserved.
#

# The main helpers and organizers for input


defmodule Scenic.ViewPort.Input do
  alias Scenic.Scene
  alias Scenic.Utilities
  alias Scenic.Graph
  alias Scenic.ViewPort
  alias Scenic.Primitive
  alias Scenic.Math.MatrixBin, as: Matrix

  require Logger

  import IEx

  defmodule Context do
    alias Scenic.Math.MatrixBin, as: Matrix
    @identity         Matrix.identity()
    defstruct scene: nil, tx: @identity, inverse_tx: @identity, uid: nil
  end

  @ets_graphs_table       :_scenic_viewport_graphs_table_

  @identity         Matrix.identity()

  #============================================================================
  # input handling

  #--------------------------------------------------------
  # ignore input until a scene has been set
  def handle_cast( {:input, _}, %{root_scene: nil} = state ) do
    {:noreply, state}
  end

  #--------------------------------------------------------
  # Input handling is enough of a beast to put move it into it's own section below
  # bottom of this file.
  def handle_cast( {:input, {input_type, _} = input_event}, 
  %{input_captures: input_captures} = state ) do
    case Map.get(input_captures, input_type) do
      nil ->
        # regular input handling
        do_handle_input(input_event, state)

      context ->
        # captive input handling
        do_handle_captured_input(input_event, context, state)
    end
  end

  #--------------------------------------------------------
  # capture a type of input
  def handle_cast( {:capture_input, scene_ref, input_types},
  %{input_captures: captures} = state ) do
    captures = Enum.reduce(input_types, captures, fn(input_type, ic)->
      Map.put( ic, input_type, scene_ref )
    end)
    {:noreply, %{state | input_captures: captures}}
  end

  #--------------------------------------------------------
  # release a captured type of input
  def handle_cast( {:release_input, input_types},
  %{input_captures: captures} = state ) do
    captures = Enum.reduce(input_types, captures, fn(input_type, ic)->
      Map.delete(ic, input_type)
    end)
    {:noreply, %{state | input_captures: captures}}
  end


  #============================================================================
  # captured input handling
  # mostly events get sent straight to the capturing scene. Common events that
  # have an x,y point, get transformed into the scene's requested coordinate space.

  defp do_handle_captured_input( event, context, state )

#  defp do_handle_captured_input( _, nil, _, state ), do: {:noreply, state}
#  defp do_handle_captured_input( _, _, nil, state ), do: {:noreply, state}

  #--------------------------------------------------------
  defp do_handle_captured_input({:cursor_button, {button, action, mods, point}}, context, state ) do
    uid = find_by_captured_point( point, context, state[:max_depth] )

    Scene.cast(context.scene,
      {
        :input,
        { :cursor_button, {button, action, mods, point}},
        Map.put(context, :uid, uid)
      })
    {:noreply, state}
  end



  #--------------------------------------------------------
  defp do_handle_captured_input( {:cursor_scroll, {offset, point}}, context,
  %{max_depth: max_depth} = state ) do
    {uid, point} = find_by_captured_point( point, context, max_depth )

    Scene.cast(context.scene,
      {
        :input,
        {:cursor_scroll, {offset, point}},
        Map.put(context, :uid, uid)
      })
    {:noreply, state}
  end

  #--------------------------------------------------------
  # cursor_enter is only sent to the root scene
  defp do_handle_captured_input( {:cursor_enter, point}, context,
  %{max_depth: max_depth} = state ) do
    {uid, point} = find_by_captured_point( point, context, max_depth )

    Scene.cast(context.scene,
      {
        :input,
        {:cursor_enter, point},
        Map.put(context, :uid, uid)
      })
    {:noreply, state}
  end

  #--------------------------------------------------------
  # cursor_exit is only sent to the root scene
  defp do_handle_captured_input( {:cursor_exit, point}, context,
  %{max_depth: max_depth} = state ) do
    {uid, point} = find_by_captured_point( point, context, max_depth )
    Scene.cast(context.scene,
      {
        :input,
        {:cursor_enter, point},
        Map.put(context, :uid, uid)
      })
    {:noreply, state}
  end

  #--------------------------------------------------------
  # cursor_enter is only sent to the root scene
  defp do_handle_captured_input( {:cursor_pos, point} = msg, context,
  %{root_scene: root_scene, max_depth: max_depth} = state ) do
    case find_by_captured_point( point, context, max_depth ) do
      {nil, point} ->
        # no uid found. let the capturing scene handle the raw positino
        # we already know the root scene has identity transforms
        state = send_primitive_exit_message(state)
        Scene.cast(context.scene,
          {
            :input,
            {:cursor_pos, point},
            Map.put(context, :uid, nil)
          })
        {:noreply, state}

      {uid, point} ->
        # get the graph key, so we know what scene to send the event to
        state = send_enter_message( uid, context.scene, state )
        Scene.cast(context.scene,
          {
            :input,
            {:cursor_pos, point},
            Map.put(context, :uid, uid)
          })
        {:noreply, state}
    end
  end


  #--------------------------------------------------------
  # all events that don't need a point transformed
  defp do_handle_captured_input( event, context, state ) do
    Scene.cast(context.scene,
      { :input, event, Map.put(context, :uid, nil) })
    {:noreply, state}
  end


  #============================================================================
  # regular input handling

  # note. if at any time a scene wants to collect all the raw input and avoid
  # this filtering mechanism, it can register directly for the input

  defp do_handle_input( event, state )

  #--------------------------------------------------------
  # text codepoint input is only sent to the scene with the input focus.
  # If no scene has focus, then send the codepoint to the root scene
#  defp do_handle_input( {:codepoint, _} = msg, state ) do
#    send_input_to_focused_scene( msg, state )
#    {:noreply, state}
#  end

  #--------------------------------------------------------
  # key press input is only sent to the scene with the input focus.
  # If no scene has focus, then send the codepoint to the root scene
#  defp do_handle_input( {:key, _} = msg, state ) do
#    send_input_to_focused_scene( msg, state )
#    {:noreply, state}
#  end

  #--------------------------------------------------------
  # key press input is only sent to the scene with the input focus.
  # If no scene has focus, then send the codepoint to the root scene
  defp do_handle_input( {:cursor_button, {button, action, mods, point}} = msg,
  %{root_scene: root_scene} = state ) do
    case find_by_screen_point( point, state ) do
      nil ->
        # no uid found. let the root scene handle the click
        # we already know the root scene has identity transforms
        Scene.cast( root_scene,
          {
            :input,
            msg,
            %Context{ scene: root_scene }
          })

      {point, {uid, scene}, {tx, inv_tx}} ->
        Scene.cast( scene,
          {
            :input,
            {:cursor_button, {button, action, mods, point}},
            %Context{
              scene: scene,
              uid: uid,
              tx: tx, inverse_tx: inv_tx
            }
          })
    end
    {:noreply, state}
  end

  #--------------------------------------------------------
  # key press input is only sent to the scene with the input focus.
  # If no scene has focus, then send the codepoint to the root scene
  defp do_handle_input( {:cursor_scroll, {offset, point}} = msg,
  %{root_scene: root_scene} = state ) do

    case find_by_screen_point( point, state ) do
      nil ->
        # no uid found. let the root scene handle the click
        # we already know the root scene has identity transforms
        Scene.cast(root_scene, {:input, msg, %{graph_ref: root_scene}} )

      {point, {uid, scene}, {tx, inv_tx}} ->
        # get the graph key, so we know what scene to send the event to
        Scene.cast( scene,
          {
            :input,
            {:cursor_scroll, {offset, point}},
            %Context{
              scene: scene,
              uid: uid,
              tx: tx, inverse_tx: inv_tx,
            }
          })
    end
    {:noreply, state}
  end

  #--------------------------------------------------------
  # cursor_enter is only sent to the root scene
  defp do_handle_input( {:cursor_pos, point} = msg,
  %{root_scene: root_scene} = state ) do
    state = case find_by_screen_point( point, state ) do
      nil ->
        # no uid found. let the root scene handle the event
        # we already know the root scene has identity transforms
        state = send_primitive_exit_message(state)
        Scene.cast(root_scene, {:input, msg, %Context{scene: root_scene}} )
        state

      {point, {uid, scene}, _} ->
        # get the graph key, so we know what scene to send the event to
        state = send_enter_message( uid, scene, state )
        Scene.cast( scene,
          {
            :input,
            {:cursor_pos, point},
            %Context{scene: scene, uid: uid}
          })
        state
    end

    {:noreply, state}
  end

  #--------------------------------------------------------
  # cursor_enter is only sent to the root scene so no need to transform it
  defp do_handle_input( {:viewport_enter, _} = msg, %{root_scene: root_scene} = state ) do
    Scene.cast( root_scene,
      {
        :input,
        msg,
        %Context{ scene: root_scene }
      })
    {:noreply, state}
  end

  #--------------------------------------------------------
  # Any other input (non-standard, generated, etc) get sent to the root scene
  defp do_handle_input( msg, %{root_scene: root_scene} = state ) do
    Scene.cast( root_scene,
      {
        :input,
        msg,
        %Context{ scene: root_scene }
      })
    {:noreply, state}
  end

  
  #============================================================================
  # regular input helper utilties

  defp send_primitive_exit_message( %{hover_primitve: nil} = state ), do: state
  defp send_primitive_exit_message( %{hover_primitve: {uid, scene}} = state ) do
    Scene.cast( scene,
      {
        :input,
        {:cursor_exit, uid},
        %Context{uid: uid, scene: scene}
      })
    %{state | hover_primitve: nil}
  end

  defp send_enter_message( uid, scene, %{hover_primitve: hover_primitve} = state ) do
    # first, send the previous hover_primitve an exit message
    state = case hover_primitve do
      nil ->
        # no previous hover_primitive set. do not send an exit message
        state

      {^uid, ^scene} ->
        # stil in the same hover_primitive. do not send an exit message
        state

      _ -> 
        # do send the exit message
        send_primitive_exit_message( state )
    end

    # send the new hover_primitve an enter message
    state = case state.hover_primitve do
      nil ->
        # yes. setting a new one. send it.
        Scene.cast( scene,
          {
            :input,
            {:cursor_enter, uid},
            %Context{uid: uid, scene: scene}
          })
        %{state | hover_primitve: {uid, scene}}

      _ ->
        # not setting a new one. do nothing.
        state
    end
    state
  end



  #--------------------------------------------------------
  # find the indicated primitive in a single graph. use the incoming parent
  # transforms from the context
  defp find_by_captured_point( point, context, max_depth ) do
    # project the point by that inverse matrix to get the local point
    point = Matrix.project_vector( context.inverse_tx, point )
    case ViewPort.get_graph( context.scene ) do
      nil ->
        {nil, point}
      graph ->
        case do_find_by_captured_point( point, 0, graph, @identity, @identity, max_depth ) do
          nil -> {nil, point}
          out -> out
        end
    end
  end

  defp do_find_by_captured_point( point, _, graph, _, _, 0 ) do
    Logger.error "do_find_by_captured_point max depth"
    {nil, point}
  end

  defp do_find_by_captured_point( point, _, nil, _, _, _ ) do
    Logger.warn "do_find_by_captured_point nil graph"
    {nil, point}
  end

  defp do_find_by_captured_point( point, uid, graph,
  parent_tx, parent_inv_tx, depth ) do
    # get the primitive to test
    case Map.get(graph, uid) do
      # do nothing if the primitive is hidden
      %{styles: %{hidden: true}} ->
        nil

      # if this is a group, then traverse the members backwards
      # backwards is important as the goal is to find the LAST item drawn
      # that is under the point in question
      %{data: {Primitive.Group, ids}} = p ->
        {tx, inv_tx} = calc_transforms(p, parent_tx, parent_inv_tx)
        ids
        |> Enum.reverse()
        |> Enum.find_value( fn(uid) ->
          do_find_by_captured_point( point, uid, graph, tx, inv_tx, depth - 1 )
        end)

      # This is a regular primitive, test to see if it is hit
      %{data: {mod, data}} = p ->
        {_, inv_tx} = calc_transforms(p, parent_tx, parent_inv_tx)

        # project the point by that inverse matrix to get the local point
        local_point = Matrix.project_vector( inv_tx, point )

        # test if the point is in the primitive
        case mod.contains_point?( data, local_point ) do
          true  ->
            {uid, point}

          false ->
            nil
        end
    end
  end


  #--------------------------------------------------------
  # find the indicated primitive in the graph given a point in screen coordinates.
  # to do this, we need to project the point into primitive local coordinates by
  # projecting it with the primitive's inverse final matrix.
  # 
  # Since the last primitive drawn is always on top, we should walk the tree
  # backwards and return the first hit we find. We could just reduct the whole
  # thing and return the last one found (that was my first try), but this is
  # more efficient as we can stop as soon as we find the first one.
  defp find_by_screen_point( {x,y}, %{root_scene: root_scene, max_depth: depth} = state) do
    identity = {@identity, @identity}
    do_find_by_screen_point( x, y, 0, root_scene, ViewPort.get_graph(root_scene),
      identity, identity, depth )
  end


  defp do_find_by_screen_point( _, _, _, _, _, _, _, 0 ) do
    Logger.error "do_find_by_screen_point max depth"
    nil
  end


  defp do_find_by_screen_point( _, _, _, _, nil, _, _, _ ) do
    # for whatever reason, the graph hasn't been put yet. just return nil
    nil
  end

  defp do_find_by_screen_point( x, y, uid, scene, graph,
    {parent_tx, parent_inv_tx}, {graph_tx, graph_inv_tx}, depth ) do

    # get the primitive to test
    case graph[uid] do
      # do nothing if the primitive is hidden
      %{styles: %{hidden: true}} ->
        nil

      # if this is a group, then traverse the members backwards
      # backwards is important as the goal is to find the LAST item drawn
      # that is under the point in question
      %{data: {Primitive.Group, ids}} = p ->
        {tx, inv_tx} = calc_transforms(p, parent_tx, parent_inv_tx)
        ids
        |> Enum.reverse()
        |> Enum.find_value( fn(uid) ->
          do_find_by_screen_point(
            x, y, uid, scene, graph,
            {tx, inv_tx}, {graph_tx, graph_inv_tx}, depth - 1
          )
        end)

      # if this is a SceneRef, then traverse into the next graph
      %{data: {Primitive.SceneRef, scene_ref}} = p ->
        case Scene.to_pid( scene_ref ) do
          {:ok, scene_pid} ->
            {tx, inv_tx} = calc_transforms(p, parent_tx, parent_inv_tx)
            do_find_by_screen_point(x, y, 0, scene_ref, ViewPort.get_graph(scene_ref),
              {tx, inv_tx}, {tx, inv_tx}, depth - 1
            )
          _ ->
            nil
        end

      # This is a regular primitive, test to see if it is hit
      %{data: {mod, data}} = p ->
        {_, inv_tx} = calc_transforms(p, parent_tx, parent_inv_tx)

        # project the point by that inverse matrix to get the local point
        local_point = Matrix.project_vector( inv_tx, {x, y} )

        # test if the point is in the primitive
        case mod.contains_point?( data, local_point ) do
          true  ->
            # Return the point in graph coordinates. Local was good for the hit test
            # but graph coords makes more sense for the scene logic
            graph_point = Matrix.project_vector( graph_inv_tx, {x, y} )
            {graph_point, {uid, scene}, {graph_tx, graph_inv_tx}}
          false -> nil
        end
    end
  end


  defp calc_transforms(p, parent_tx, parent_inv_tx) do
    p
    |> Map.get(:transforms, nil)
    |> Primitive.Transform.calculate_local()
    |> case do
      nil ->
        # No local transform. This will often be the case.
        {parent_tx, parent_inv_tx}

      tx ->
        # there was a local transform. multiply it into the parent
        # then also calculate a new inverse transform
        tx = Matrix.mul( parent_tx, tx )
        inv_tx = Matrix.invert( tx )
        {tx, inv_tx}
    end
  end


end













