#!/usr/bin/env python3
"""Checks that each school has its own projectile and impact visuals.

    python tests/test_spell_visuals.py -v
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CASTER = ROOT / "spell_caster.gd"
PROJECTILE = ROOT / "spell_projectile.gd"
HUD = ROOT / "hud.gd"
PLAYER = ROOT / "player.gd"
SMOKE = ROOT / "tests" / "smoke_gameplay.gd"
VISUALS = ROOT / "spell_visuals.gd"


class SpellVisualTests(unittest.TestCase):
    def test_all_spells_declare_a_visual(self):
        text = CASTER.read_text(encoding="utf-8")
        for spell, visual in (
            ("fire_bolt", "fire"), ("wind_gust", "wind"),
            ("water_jet", "water"), ("stone_shard", "earth"),
        ):
            self.assertIn('"visual": "%s"' % visual, text, spell)

    def test_caster_delegates_visuals_to_projectile(self):
        text = CASTER.read_text(encoding="utf-8")
        # Снаряд берётся из пула: configure() уже сделан при сборке, на касте
        # остаются только перекраска, позиция и запуск.
        self.assertIn("var proj := pool.acquire(str(data.get(\"visual\", \"\")))", text)
        self.assertIn("proj.apply_tint(data[\"color\"], str(data.get(\"visual\", \"\")))", text)
        self.assertIn("proj.launch()", text)
        self.assertNotIn("SphereMesh.new()", text)
        # Пул живёт в текущей сцене, а не под игроком: он общий для всех кастов.
        self.assertIn("SpellPool.get_or_create(player.get_tree())", text)

    def test_four_schools_have_distinct_geometry(self):
        """Форму задаёт геометрия, а не общий октаэдр с другой наклейкой."""
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("func _build_mesh() -> Mesh:", text)
        self.assertIn("return SpellVisuals.body_mesh(visual)", text)
        visuals = VISUALS.read_text(encoding="utf-8")
        for fn in ("_flame_spindle(", "_wind_ribbons(", "_droplet(", "_rock("):
            self.assertIn("static func %s" % fn, visuals)
        self.assertIn("const KIND_FIRE := 0", visuals)
        self.assertIn("const KIND_EARTH := 3", visuals)

    def test_projectile_has_trails_and_motion(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("func _make_trail() -> GPUParticles3D:", text)
        self.assertIn("particles.name = \"SpellTrail\"", text)
        self.assertIn("ParticleProcessMaterial.new()", text)
        self.assertIn("process.gravity = Vector3(0.0, 1.5, 0.0)", text)
        self.assertIn("motion *= 0.92 + 0.16 * sin(_time * 18.0)", text)
        # Кувырок камня — вокруг оси полёта, а не вокруг мировых осей.
        self.assertIn("_spin += 3.1 * delta", text)
        self.assertIn("b = b * Basis(Vector3(0.0, 0.0, 1.0), _spin)", text)

    def test_particles_use_hard_procedural_sprites(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("static func _particle_texture(kind: String) -> ImageTexture:", text)
        self.assertIn("static var _particle_textures: Dictionary = {}", text)
        for kind in ("spark", "streak", "droplet", "shard"):
            self.assertIn('"%s":' % kind, text)
        self.assertIn('particle_material("soft",', text)
        self.assertIn("mat.albedo_texture = _particle_texture(kind)", text)
        self.assertIn("particles.draw_passes = 1", text)
        self.assertNotIn("particles.draw_pass_2 = core", text)
        self.assertIn("sdf = maxf(absf(d.x)", text)

    def test_impacts_match_each_school(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("func _spawn_impact(body: Node3D, normal: Vector3", text)
        self.assertIn("func _make_burst(", text)
        self.assertIn("var torus := TorusMesh.new()", text)
        self.assertIn("fx.name = \"SpellImpact\"", text)
        self.assertIn("var burn: Variant = body.get(\"burn_timer\")", text)
        self.assertIn("scene = get_parent()", text)
        self.assertIn("get_tree().create_timer(0.9, true, false, true)", text)
        self.assertIn("body.call(\"on_spell_effect\", effect)", text)

    def test_impact_has_light_flash_and_normal_oriented_ring(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("_apply_hit(body, hit.normal)", text)
        self.assertIn("func _apply_hit(body: Node3D, normal: Vector3", text)
        self.assertIn("static func _ring_basis(normal: Vector3) -> Basis:", text)
        self.assertIn("ring.basis = _ring_basis(n)", text)
        self.assertIn("flash.name = \"ImpactFlash\"", text)
        self.assertIn("flash.light_energy = flash_energy", text)
        self.assertIn("tween_property(flash, \"light_energy\", 0.0", text)

    def test_particles_fade_and_scale_over_lifetime(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("static func _fade_ramp(", text)
        self.assertIn("static func _scale_curve(", text)
        self.assertIn("GradientTexture1D.new()", text)
        self.assertIn("CurveTexture.new()", text)
        self.assertIn("process.color_ramp = _fade_ramp(", text)
        self.assertIn("process.scale_curve = _scale_curve(", text)
        self.assertIn("mat.vertex_color_use_as_albedo = true", text)

    def test_cast_has_anticipation_windup(self):
        text = CASTER.read_text(encoding="utf-8")
        # 0.12 с — 7 кадров: антиципация не читается. 0.2 с читается как замах.
        self.assertIn("const CAST_WINDUP := 0.2", text)
        self.assertIn("const CAST_HAND_OFFSET := Vector3(", text)
        self.assertIn("func _launch(id: String) -> void:", text)
        self.assertIn("func _spawn_cast_fx(cam: Camera3D, tint: Color, visual_kind: String) -> void:", text)
        # Сбор энергии и вылет снаряда идут из одной точки у «руки», а не из
        # центра объектива.
        self.assertIn("func cast_hand_position(cam: Camera3D) -> Vector3:", text)
        self.assertIn("proj.global_position = cast_hand_position(cam)", text)
        self.assertIn("fx.global_position = cast_hand_position(cam)", text)
        self.assertIn("fx.name = \"CastGather\"", text)
        self.assertIn("create_timer(CAST_WINDUP).timeout.connect(_launch.bind(id))", text)
        self.assertIn("player.apply_cast_recoil(", text)
        # Спавн снаряда перенесён в _launch, а не выполняется мгновенно.
        launch = text.split("func _launch(id: String) -> void:", 1)[1]
        self.assertIn("proj.speed = data[\"speed\"] * speed_multiplier", launch)
        self.assertIn("pool.acquire(", launch)
        self.assertIn("proj.launch()", launch)

    def test_player_has_cast_recoil(self):
        text = PLAYER.read_text(encoding="utf-8")
        self.assertIn("var cast_fov_kick: float = 0.0", text)
        self.assertIn("func apply_cast_recoil(", text)
        self.assertIn("sprint_blend) + cast_fov_kick", text)

    def test_projectile_has_inertia_not_a_laser(self):
        # Постоянная скорость и прямая линия — главная причина, по которой
        # снаряд читается как «объект создан в направлении прицела».
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("func _speed_factor() -> float:", text)
        self.assertIn("* _speed_factor() * delta", text)
        # Земля летит по дуге, а не по прямой.
        self.assertIn("Vector3(0.0, -7.5 * _time + 2.2, 0.0) * delta", text)
        # Снаряд «выстреливается» из руки, а не появляется готовым.
        self.assertIn("_mesh.scale = Vector3.ONE * 0.35", text)

    def test_body_is_oriented_along_flight(self):
        """Тело строится вдоль +Z и обязано поворачиваться по направлению.

        Без этого камера видела снаряд сбоку: вытянутое веретено и струя
        читались прямоугольником — отсюда жалобы на «параллелепипеды».
        """
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("func _align_body() -> void:", text)
        self.assertIn("var b := Basis.looking_at(-dir, Vector3.UP)", text)
        # Вызывается и при запуске, и каждый кадр (у камня дуга).
        launch = text.split("func launch() -> void:", 1)[1].split("func ", 1)[0]
        self.assertIn("_align_body()", launch)
        self.assertIn("\n\t_align_body()\n", text)
        # Кувырок камня не должен перебивать ориентацию вращением узла целиком.
        self.assertNotIn("_mesh.rotation += Vector3(", text)
        self.assertNotIn("_mesh.rotation.z += 2.2 * delta", text)

    def test_fire_light_flickers(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("var _light: OmniLight3D = null", text)
        self.assertIn("_light = OmniLight3D.new()", text)
        self.assertIn("_light.light_energy = 2.4 + 0.35 * sin(_time * 21.0)", text)

    def test_impact_leaves_decal(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("static func _decal_texture(kind: String) -> ImageTexture:", text)
        for kind in ("scorch", "wet", "crack"):
            self.assertIn('"%s"' % kind, text)
        self.assertIn("func _spawn_decal(scene: Node, normal: Vector3, kind: String) -> void:", text)
        self.assertIn("decal.name = \"SpellDecal\"", text)
        self.assertIn("Decal.new()", text)
        self.assertIn("Basis.looking_at(-normal", text)
        self.assertIn("fade.tween_property(decal, \"modulate\"", text)
        self.assertIn("decal.queue_free", text)

    def test_spell_audio_is_procedural(self):
        audio = (ROOT / "spell_audio.gd").read_text(encoding="utf-8")
        self.assertIn("class_name SpellAudio", audio)
        self.assertIn("static func cast_stream(visual: String) -> AudioStreamWAV:", audio)
        self.assertIn("static func impact_stream(visual: String) -> AudioStreamWAV:", audio)
        for key in ("cast_fire", "cast_wind", "cast_water", "cast_earth",
                    "impact_fire", "impact_wind", "impact_water", "impact_earth"):
            self.assertIn('"%s"' % key, audio)
        self.assertIn("AudioStreamWAV.new()", audio)
        self.assertIn("rng.seed = ", audio)
        self.assertIn("player.finished.connect(player.queue_free)", audio)

    def test_audio_hooked_into_cast_and_impact(self):
        caster = CASTER.read_text(encoding="utf-8")
        self.assertIn("SpellAudio.cast_stream(", caster)
        self.assertIn('"CastAudio"', caster)
        projectile = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("SpellAudio.impact_stream(visual)", projectile)
        self.assertIn('"ImpactAudio"', projectile)

    def test_each_school_has_its_own_material(self):
        """Общий шейдер на четыре разные материи — источник всех жалоб."""
        visuals = VISUALS.read_text(encoding="utf-8")
        for fn in ("_flame_shader(", "_air_shader(", "_liquid_shader(",
                   "_stone_shader("):
            self.assertIn("static func %s" % fn, visuals)
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("func _body_material() -> Material:", text)
        self.assertIn("return SpellVisuals.body_material(visual, tint)", text)
        # Старого единого шейдера с mode=0/1/2 больше нет.
        self.assertNotIn("var modes := {\"fire\": 0.0", text)
        self.assertNotIn("render_mode blend_mix, cull_disabled, depth_draw_opaque;", text)

    def test_smoke_and_turbulence(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("func _make_smoke() -> GPUParticles3D:", text)
        self.assertIn("particles.name = \"SpellSmoke\"", text)
        self.assertIn('quad.material = particle_material("soft", Color(0.16', text)
        self.assertIn("process.scale_curve = _scale_curve(0.7, 2.4)", text)
        self.assertIn("process.turbulence_enabled = true", text)
        self.assertIn("process.turbulence_noise_speed = Vector3(0.8, 0.8, 0.8)", text)
        self.assertIn("process.turbulence_noise_strength = 0.4 if kind == \"spark\" else 0.6", text)

    def test_heavy_hitstop(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("static var _hitstop_active: bool = false", text)
        self.assertIn("func _heavy_hitstop() -> void:", text)
        self.assertIn("Engine.time_scale = 0.15", text)
        self.assertIn("create_timer(0.045, true, false, true)", text)
        self.assertIn("if visual == \"earth\":", text)

    def test_flight_audio(self):
        audio = (ROOT / "spell_audio.gd").read_text(encoding="utf-8")
        self.assertIn("static func flight_stream(visual: String) -> AudioStreamWAV:", audio)
        self.assertIn("AudioStreamWAV.LOOP_FORWARD", audio)
        for key in ("flight_fire", "flight_wind", "flight_water", "flight_earth"):
            self.assertIn('"%s"' % key, audio)
        projectile = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("SpellAudio.flight_stream(visual)", projectile)
        self.assertIn('"SpellFlightAudio"', projectile)

    def test_fire_looks_like_fire_not_a_lamp(self):
        """Огонь светится в ядре, а не по контуру силуэта."""
        visuals = VISUALS.read_text(encoding="utf-8")
        flame = visuals.split("static func _flame_shader()", 1)[1] \
            .split("static func _air_shader()", 1)[0]
        # Адвекция вдоль оси с двумя фазами и crossfade.
        self.assertIn("fbm3(", flame)
        self.assertIn("float phase = fract(TIME * speed * 0.55);", flame)
        self.assertIn("mix(d0, d1, w)", flame)
        # Эрозия по высоте: язык рвётся к хвосту.
        self.assertIn("density -= axis * 0.55;", flame)
        # Четыре ступени ramp и намеренно холодная кайма.
        self.assertIn("vec3 body = tint.rgb * 0.45;", flame)
        self.assertIn("vec3 core = vec3(1.0, 0.96, 0.86);", flame)
        self.assertIn("vec3 cool =", flame)
        # Яркость живёт в ядре (источник света), а не на кромке силуэта.
        self.assertIn("EMISSION = col * pow(heat, 1.35)", flame)
        self.assertNotIn("pow(1.0 - facing, 2.5)", flame)
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("_light.shadow_enabled = true", text)

    def test_wind_matches_reference_layers(self):
        """Ветер как на референсе Romain Coste: слои, а не одна труба.

        Там читается: мягкие закрученные ленты, яркий полумесяц-наконечник,
        тонкие штрихи скорости и мусор в вихре.
        """
        visuals = VISUALS.read_text(encoding="utf-8")
        for fn in ("_wind_ribbons(", "_wind_crescent("):
            self.assertIn("static func %s" % fn, visuals)
        # Ленты идут по спирали: угол растёт вдоль оси.
        ribbons = visuals.split("static func _wind_ribbons()", 1)[1] \
            .split("static func _wind_crescent()", 1)[0]
        self.assertIn("var twist := 9.0 + float(k) * 1.7", ribbons)
        self.assertIn("var a := phase + t * twist", ribbons)
        air = visuals.split("static func _air_shader()", 1)[1] \
            .split("static func _liquid_shader()", 1)[0]
        # Светлая слоистая дымка с мягкой альфой, а не неон.
        self.assertIn("float density = smoothstep(0.25, 0.85", air)
        self.assertIn("vec3 plume = tint.rgb * (0.55 + 0.65 * density);", air)
        # Наконечник ярче остального тела.
        self.assertIn("plume += tint.rgb * core_boost * 1.6;", air)
        self.assertIn("uniform float core_boost = 0.0;", air)
        # Преломление осталось добавкой, а не основой.
        self.assertIn("hint_screen_texture", air)
        self.assertIn("uniform float distortion = 0.02;", air)

        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("func _build_wind_extras() -> void:", text)
        self.assertIn('crescent.name = "WindCrescent"', text)
        self.assertIn('streaks.name = "WindStreaks"', text)
        self.assertIn('c_mat.set_shader_parameter("core_boost", 1.0)', text)
        # Штрихи скорости летят назад от наконечника.
        self.assertIn("sp.direction = Vector3(0.0, 0.0, -1.0)", text)

    def test_water_is_transparent_liquid(self):
        """Вода: преломление, fresnel и поглощение по толщине, не заливка."""
        visuals = VISUALS.read_text(encoding="utf-8")
        water = visuals.split("static func _liquid_shader()", 1)[1] \
            .split("static func _stone_shader()", 1)[0]
        self.assertIn("hint_screen_texture", water)
        self.assertIn("float fresnel = 0.02 + 0.98 * pow(1.0 - facing, 4.5);", water)
        # Закон Бера — Ламберта: цвет гасится по толщине слоя.
        self.assertIn("vec3 sigma = vec3(1.0, 0.55, 0.32) * absorption;", water)
        self.assertIn("vec3 transmittance = exp(-sigma * thickness);", water)
        self.assertIn("float thickness = 0.22 * sqrt(max(1.0 - radial * radial, 0.0));", water)
        # v_local обязан присваиваться в vertex, иначе толщина нулевая.
        self.assertIn("void vertex() {", water)
        self.assertIn("v_local = VERTEX;", water)
        self.assertIn("ROUGHNESS = 0.02;", water)
        # Никакой постоянной альфы-заливки.
        self.assertNotIn("ALPHA = 0.55 + rim * 0.4;", water)

    def test_earth_is_hard_not_blurry(self):
        """Камень: фасетки и матовый материал, а не растущая клякса пыли."""
        visuals = VISUALS.read_text(encoding="utf-8")
        stone = visuals.split("static func _stone_shader()", 1)[1]
        self.assertIn("float crevice = smoothstep(0.62, 0.78", stone)
        self.assertIn("ROUGHNESS = 0.94", stone)
        self.assertNotIn("EMISSION", stone)
        text = PROJECTILE.read_text(encoding="utf-8")
        # Пыль больше не растёт в 2.6 раза — именно это «мылило» камень.
        self.assertNotIn("_scale_curve(0.6, 2.6)", text)
        self.assertIn("particles.amount = 12", text)
        # Осколки — главный элемент удара камня, их больше и они быстрее.
        self.assertIn('_make_burst(16, Color(0.46, 0.39, 0.32, 0.95)', text)

    def test_only_fire_glows_on_surface(self):
        """Пятно света после удара — физически только у огня."""
        text = PROJECTILE.read_text(encoding="utf-8")
        pool = text.split("func _spawn_glow_pool(", 1)[1] \
            .split("func _heavy_hitstop", 1)[0]
        self.assertIn("if not _emits_light():", pool)
        self.assertIn("return", pool)
        visuals = VISUALS.read_text(encoding="utf-8")
        self.assertIn("return kind_of(visual) == KIND_FIRE", visuals)

    def test_screen_post_process(self):
        fx = (ROOT / "spell_screen_fx.gd").read_text(encoding="utf-8")
        self.assertIn("class_name SpellScreenFx", fx)
        self.assertIn("extends ColorRect", fx)
        self.assertIn("shader_type canvas_item;", fx)
        for layer in ("flash", "focus", "aberration", "vignette_base"):
            self.assertIn("uniform float %s" % layer, fx)
        self.assertIn("func on_cast(color: Color) -> void:", fx)
        self.assertIn("func on_impact(color: Color, distance: float, heavy: bool) -> void:", fx)
        hud = HUD.read_text(encoding="utf-8")
        self.assertIn("screen_fx = SpellScreenFx.create(self)", hud)
        self.assertIn("screen_fx.on_cast(spell_tint)", hud)
        self.assertIn("screen_fx.on_impact(spell_tint, dist, heavy)", hud)

    def test_impact_leaves_glow_on_surface(self):
        text = PROJECTILE.read_text(encoding="utf-8")
        self.assertIn("func _spawn_glow_pool(scene: Node, normal: Vector3) -> void:", text)
        self.assertIn('pool.name = "SpellGlowPool"', text)
        self.assertIn("_spawn_glow_pool(scene, n)", text)

    def test_projectiles_are_pooled(self):
        pool = (ROOT / "spell_pool.gd").read_text(encoding="utf-8")
        self.assertIn("class_name SpellPool", pool)
        self.assertIn("static func get_or_create(tree: SceneTree) -> SpellPool:", pool)
        self.assertIn("func acquire(visual: String) -> SpellProjectile:", pool)
        self.assertIn("func release(proj: SpellProjectile) -> void:", pool)
        self.assertIn('GROUP := "spell_pool"', pool)
        projectile = PROJECTILE.read_text(encoding="utf-8")
        # Попадание больше не удаляет узел: снаряд возвращается в пул.
        self.assertIn("func _recycle() -> void:", projectile)
        self.assertIn("pool.call(\"release\", self)", projectile)
        self.assertIn("func launch() -> void:", projectile)
        self.assertNotIn("_spawn_impact(body, normal)\n\tqueue_free()", projectile)
        caster = CASTER.read_text(encoding="utf-8")
        self.assertIn("pool.acquire(", caster)
        self.assertNotIn("SpellProjectile.new()", caster)

    def test_smoke_checks_distinct_projectiles(self):
        text = SMOKE.read_text(encoding="utf-8")
        self.assertIn("four schools create distinct projectiles with trails", text)
        self.assertIn("func _spell_projectiles_distinct(", text)
        self.assertIn('"SpellSmoke"', text)
        self.assertIn("hitstop", text)
        self.assertIn("_pool_reuses_projectile(", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
