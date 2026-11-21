"""OSM structure classification and shared USGS road grade."""

def is_bridge(tags):
    """A layer alone does not prove a bridge. Exclude underground structures."""
    if tags.get('tunnel') not in (None, '', 'no'):
        return False
    bridge = tags.get('bridge', '').strip().lower()
    if bridge in ('', 'no', 'false', '0'):
        return False
    try:
        layer = int(tags.get('layer', '0'))
    except (ValueError, TypeError):
        layer = 0
    return layer >= 0


def ground_grade(dem, x, z):
    return dem(x, z) + .078


def smoothstep(value):
    t = min(1., max(0., float(value)))
    return t*t*(3.-2.*t)


def surface_grade(dem, line, station, point):
    """Smooth short raster features while staying within 45 cm of the DEM."""
    base = float(ground_grade(dem, *point))
    radius = min(9., float(station), line.length - float(station))
    if radius <= .001:
        return base
    ends = [float(ground_grade(dem, *line.interpolate(station + u*radius).coords[0]))
            for u in (-1., -.5, .5, 1.)]
    delta = (sum(ends) + 2.*base)/6.-base
    return base + min(.45, max(-.45, delta))
