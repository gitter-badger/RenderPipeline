"""

RenderPipeline

Copyright (c) 2014-2016 tobspr <tobias.springer1@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

"""

from __future__ import division

from functools import partial
from rplibs.six.moves import range

from panda3d.core import Vec4, Vec3, Vec2, RenderState, TransformState
from panda3d.core import TexturePool, SceneGraphAnalyzer
from direct.interval.IntervalGlobal import Sequence

from rpcore.gui.sprite import Sprite
from rpcore.gui.buffer_viewer import BufferViewer
from rpcore.gui.pipe_viewer import PipeViewer
from rpcore.gui.render_mode_selector import RenderModeSelector

from rpcore.gui.text_node import TextNode
from rpcore.gui.error_message_display import ErrorMessageDisplay
from rpcore.gui.exposure_widget import ExposureWidget
from rpcore.gui.fps_chart import FPSChart
from rpcore.gui.pixel_inspector import PixelInspector

from rpcore.globals import Globals
from rpcore.rpobject import RPObject

from rpcore.native import NATIVE_CXX_LOADED
from rpcore.render_target import RenderTarget
from rpcore.image import Image

class Debugger(RPObject):

    """ This class manages the onscreen gui and """

    def __init__(self, pipeline):
        RPObject.__init__(self)
        self.debug("Creating debugger")
        self._pipeline = pipeline
        self._analyzer = SceneGraphAnalyzer()

        self._load_config()
        self._fullscreen_node = Globals.base.pixel2d.attach_new_node(
            "PipelineDebugger")
        self._create_components()
        self._init_keybindings()
        self._init_notify()

        Globals.base.doMethodLater(
            0.5, lambda task: self._collect_scene_data(), "RPDebugger_collectSceneData_initial")
        Globals.base.doMethodLater(0.1, self._update_stats, "RPDebugger_updateStats")

    def _load_config(self):
        """ Loads the gui configuration from config/debugging.yaml """
        

    def _create_components(self):
        """ Creates the gui components """

        # When using small resolutions, scale the GUI so its still useable,
        # otherwise the sub-windows are bigger than the main window
        scale_factor = min(1.0, Globals.base.win.get_x_size() / 1920.0)
        self._fullscreen_node.set_scale(scale_factor)
        self._gui_scale = scale_factor

        # Component values
        self._debugger_width = 460

        # Create states
        self._debugger_visible = False

        # Create intervals
        self._debugger_interval = None

        # Create the actual GUI
        self._create_topbar()
        self._create_stats()
        self._create_hints()

        self._exposure_node = self._fullscreen_node.attach_new_node("ExposureWidget")
        self._exposure_node.set_pos(
            Globals.base.win.get_x_size() / self._gui_scale - 200,
            1, -Globals.base.win.get_y_size() / self._gui_scale + 120)
        self._exposure_widget = ExposureWidget(self._pipeline, self._exposure_node)

        self._fps_node = self._fullscreen_node.attach_new_node("FPSChart")
        self._fps_node.set_pos(Vec3(21, 1, -108 - 40))
        self._fps_widget = FPSChart(self._pipeline, self._fps_node)

        self._pixel_widget = PixelInspector(self._pipeline)

        self._buffer_viewer = BufferViewer(self._pipeline, self._fullscreen_node)
        self._pipe_viewer = PipeViewer(self._pipeline, self._fullscreen_node)
        self._rm_selector = RenderModeSelector(self._pipeline, self._fullscreen_node)

    def _init_notify(self):
        """ Inits the notify stream which gets all output from panda and parses
        it """
        self._error_msg_handler = ErrorMessageDisplay()

    def update(self):
        """ Updates the gui """
        self._error_msg_handler.update()
        self._pixel_widget.update()

    def get_error_msg_handler(self):
        """ Returns the error message handler """
        return self._error_msg_handler

    def _create_topbar(self):
        """ Creates the topbar """
        self._pipeline_logo = Sprite(
            image="/$$rp/data/gui/pipeline_logo_text.png", x=30, y=50,
            parent=self._fullscreen_node)

    def _collect_scene_data(self, task=None):
        """ Analyzes the scene graph to provide useful information """
        self._analyzer.clear()
        for geom_node in Globals.base.render.find_all_matches("**/+GeomNode"):
            self._analyzer.add_node(geom_node.node())
        if task:
            return task.again

    def _create_stats(self):
        """ Creates the stats overlay """
        self._overlay_node = Globals.base.aspect2d.attach_new_node("Overlay")
        self._overlay_node.set_pos(Globals.base.get_aspect_ratio() - 0.07, 1, 1.0 - 0.07)
        self._debug_lines = []
        for i in range(5):
            self._debug_lines.append(TextNode(
                pos=Vec2(0, -i * 0.046), parent=self._overlay_node,
                pixel_size=16, align="right", color=Vec3(1)))

    def _create_hints(self):
        """ Creates the hints like keybindings and when reloading shaders """
        self._hint_reloading = Sprite(
            image="/$$rp/data/gui/shader_reload_hint.png",
            x=float((Globals.base.win.get_x_size()) // 2) / self._gui_scale - 465 // 2, y=220,
            parent=self._fullscreen_node)
        self.set_reload_hint_visible(False)

        if not NATIVE_CXX_LOADED:
            # Warning when using the python version
            python_warning = Sprite(
                image="/$$rp/data/gui/python_warning.png",
                x=((Globals.base.win.get_x_size()/self._gui_scale) - 1054) // 2,
                y=(Globals.base.win.get_y_size()/self._gui_scale) - 118 - 40,
                parent=self._fullscreen_node)

            Sequence(
                python_warning.color_scale_interval(0.7, Vec4(0.3, 1, 1, 0.7), blendType="easeOut"),
                python_warning.color_scale_interval(0.7, Vec4(1, 1, 1, 1.0), blendType="easeOut"),
            ).loop()

        # Keybinding hints
        self._keybinding_instructions = Sprite(
            image="/$$rp/data/gui/keybindings.png", x=30,
            y=Globals.base.win.get_y_size()//self._gui_scale - 510.0,
            parent=self._fullscreen_node, any_filter=False)

    def _update_stats(self, task=None):
        """ Updates the stats overlay """
        clock = Globals.clock
        self._debug_lines[0].text = "{:3.0f} fps  |  {:3.1f} ms  |  {:3.1f} ms max".format(
            clock.get_average_frame_rate(),
            1000.0 / max(0.001, clock.get_average_frame_rate()),
            clock.get_max_frame_duration() * 1000.0)

        text = "{:4d} render states  |  {:4d} transforms"
        text += "  |  {:4d} commands  |  {:4d} lights  |  {:5d} shadow sources  "
        text += "|  {:3.1f}% atlas usage"
        self._debug_lines[1].text = text.format(
            RenderState.get_num_states(), TransformState.get_num_states(),
            self._pipeline.light_mgr.cmd_queue.num_processed_commands,
            self._pipeline.light_mgr.num_lights,
            self._pipeline.light_mgr.num_shadow_sources,
            self._pipeline.light_mgr.shadow_atlas_coverage)

        text = "Pipeline:   {:3.0f} MiB VRAM  |  {:5d} images  |  {:5d} textures  |  "
        text += "{:5d} render targets  |  {:3d} plugins"
        tex_memory, tex_count = self._buffer_viewer.stage_information
        self._debug_lines[2].text = text.format(
            tex_memory / (1024**2), len(Image.REGISTERED_IMAGES), tex_count,
            RenderTarget.NUM_ALLOCATED_BUFFERS,
            len(self._pipeline.plugin_mgr.enabled_plugins))

        text = "Scene:   {:4.0f} MiB VRAM  |  {:3d} textures  |  {:4d} geoms  "
        text += "|  {:4d} nodes  |  {:7,.0f} vertices  |  {:5.0f} MiB vTX data  "
        scene_tex_size = 0
        for tex in TexturePool.find_all_textures():
            scene_tex_size += tex.estimate_texture_memory()

        self._debug_lines[3].text = text.format(
            scene_tex_size / (1024**2),
            len(TexturePool.find_all_textures()),
            self._analyzer.get_num_geoms(),
            self._analyzer.get_num_nodes(),
            self._analyzer.get_num_vertices(),
            self._analyzer.get_vertex_data_size() / (1024**2),
        )

        sun_vector = Vec3(0)
        if self._pipeline.plugin_mgr.is_plugin_enabled("scattering"):
            sun_vector = self._pipeline.plugin_mgr.instances["scattering"].sun_vector

        text = "{} ({:1.3f})  |  {:0.2f} {:0.2f} {:0.2f}  |  {:3d} daytime settings  |  X {:3.1f}  Y {:3.1f}  Z {:3.1f}"
        text += "    |  Total tasks:  {:2d}   |   scheduled: {:2d}"
        self._debug_lines[4].text = text.format(
            self._pipeline.daytime_mgr.formatted_time,
            self._pipeline.daytime_mgr.time,
            sun_vector.x, sun_vector.y, sun_vector.z,
            len(self._pipeline.plugin_mgr.day_settings),
            Globals.base.camera.get_x(Globals.base.render),
            Globals.base.camera.get_y(Globals.base.render),
            Globals.base.camera.get_z(Globals.base.render),
            self._pipeline.task_scheduler.num_tasks,
            self._pipeline.task_scheduler.num_scheduled_tasks,
        )

        if task:
            return task.again

    def set_reload_hint_visible(self, flag):
        """ Sets whether the shader reload hint is visible """
        if flag:
            self._hint_reloading.show()
        else:
            self._hint_reloading.hide()

    def _init_keybindings(self):
        """ Inits the debugger keybindings """
        Globals.base.accept("v", self._buffer_viewer.toggle)
        Globals.base.accept("c", self._pipe_viewer.toggle)
        Globals.base.accept("z", self._rm_selector.toggle)
        Globals.base.accept("f5", self._toggle_gui_visible)
        Globals.base.accept("f6", self._toggle_fps_visible)

    def _toggle_gui_visible(self):
        """ Shows / Hides the gui """

        if not self._fullscreen_node.is_hidden():
            self._fullscreen_node.hide()
            self._overlay_node.hide()
        else:
            self._fullscreen_node.show()
            self._overlay_node.show()

    def _toggle_fps_visible(self):
        """ Shows / Hides the FPS graph """
        if not self._fps_node.is_hidden():
            self._fps_node.hide()
        else:
            self._fps_node.show()
