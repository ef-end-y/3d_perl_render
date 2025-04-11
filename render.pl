use strict;
use Image::Magick;

my $scr_x = 800;
my $scr_y = 800;
my $scr_z = 1000;

my @light_vector = (0.1, 0, 1);

my $obj_filename = 'face.txt';
my $texture_filename = 'african_head_diffuse.tga';

# 0: без текстуры, яркость пропорциональна z-координате
# 1: без текстуры, яркость интерполяцией по нормалям в вершинах,
#    нормали берутся из описания модели
# 2: просто текстура
# 3: текстура с освещением по нормалям в вершинах
# 4: без текстуры, яркость по карте нормалей
# 5: текстура, яркость по карте нормалей

my $Mode = 3;


open(my $fh, '<:encoding(UTF-8)', $obj_filename) or die "Could not open file '$obj_filename' $!";

my $texture_image = Image::Magick->new;
my $status = $texture_image->Read($texture_filename); # or die "Could not read file '$texture_filename' $!";

my($u_max, $v_max) = $texture_image->Get('columns', 'rows');

my @vectors = ();
my @normals = ();
my @textures = ();
my @polygons = ();

my @rows = <$fh>;
chomp @rows;
foreach my $row (@rows)
{
    $row =~ /^([^\s]+)\s+([^\s]+)\s+([^\s]+)\s+([^\s]+)/ or next;
    my($cmd, @xyz) = ($1, $2, $3, $4);
    if( $cmd eq 'v' )
    {
        push @vectors, \@xyz;
    }
     elsif( $cmd eq 'vn' )
    {
        push @normals, \@xyz;
    }
     elsif( $cmd eq 'vt' )
    {
        push @textures, [ $xyz[0] * $u_max, $xyz[1] * $v_max ];
    }
     elsif( $cmd eq 'f' )
    {
        my @f = ();
        foreach my $i( @xyz )
        {
            push @f, [ map{ int($_)-1 } split /\//, $i ];
        }
        push @polygons, {
            'vectors' => [ map{ $_->[0] } @f ],
            'texture' => [ map{ $_->[1] } @f ],
            'normals' => [ map{ $_->[2] } @f ],
        };
    }
}


my @scale = ( int($scr_x / 2 - 0.5), int($scr_y / 2 - 0.5), int($scr_z / 2 - 0.5) );

Canvas->new($scr_x, $scr_y, $scr_z);


foreach my $i( @polygons )
{
    my @vectors_ = map{ $vectors[$_] }  @{$i->{vectors}};
    my @normals_ = map{ $normals[$_] }  @{$i->{normals}};
    my @texture_ = map{ $textures[$_] } @{$i->{texture}};
    my @new_vectors = ();
    foreach my $v( @vectors_ )
    {
        my @xyz = map{ $v->[$_] * $scale[$_] } (0..2);
        # Вращение
        my( $x, $y, $z ) = @xyz;
        #x = int(xyz[0] * cos(rotate) - xyz[2] * sin(rotate))
        #z = int(xyz[0] * sin(rotate) + xyz[2] * cos(rotate))
        #y = int(xyz[1])
        push @new_vectors, Vector->new($x, $y, $z);
    }
    my( $a, $b, $c ) = @new_vectors;
    ($a->{u}, $a->{v}) = @{$texture_[0]};
    ($b->{u}, $b->{v}) = @{$texture_[1]};
    ($c->{u}, $c->{v}) = @{$texture_[2]};
    my @light = ();
    foreach my $normal( @normals_ )
    {
        push @light, eval join '+', map{ $normal->[$_] * $light_vector[$_] } (0..2);
    }
    ($a->{light}, $b->{light}, $c->{light}) = @light;
    triangle($a, $b, $c);
}

Canvas->show();

exit();

sub triangle
{
    my($A, $B, $C) = sort{ $a->{y} <=> $b->{y} } @_;
    my(undef, $y, $x1, $x2, $z1, $z2, $u1, $u2, $v1, $v2, $light1, $light2) = 
        map{ $A->{$_}, $A->{$_} } ('y', 'x', 'z', 'u', 'v', 'light');
    my $point = $B;
    my $height = $C->{y} - $y;
    my $delta_cx = $height ? ($C->{x} - $x1) / $height : 0;
    my $delta_cz = $height ? ($C->{z} - $z1) / $height : 0;
    my $delta_u2 = $height ? ($C->{u} - $u1) / $height : 0;
    my $delta_v2 = $height ? ($C->{v} - $v1) / $height : 0;
    my $delta_c_light = $height ? ($C->{light} - $light1) / $height : 0;
    foreach my $step( 0, 1 )
    {
        if( $step )
        {
            $x2 -= $delta_cx;
            $z2 -= $delta_cz;
            $light2 -= $delta_c_light;
            ($y, $x1, $z1, $u1, $v1, $light1) = map{ $B->{$_} } ('y', 'x', 'z', 'u', 'v', 'light');
            $point = $C;
        }
        $height = $point->{y} - $y;
        my $delta_bx = $height ? ($point->{x} - $x1) / $height : 0;
        my $delta_bz = $height ? ($point->{z} - $z1) / $height : 0;
        my $delta_v1 = $height ? ($point->{v} - $v1) / $height : 0;
        my $delta_u1 = $height ? ($point->{u} - $u1) / $height : 0;
        my $delta_b_light = $height ? ($point->{light} - $light1) / $height : 0;
        my $dz = 0;
        my $du = 0;
        my $dv = 0;
        my $dl = 0;
        while( $y <= $point->{y} )
        {
            if( $x1 != $x2 && !$dz )
            {
                my $width = $x2 - $x1;
                $dz = ($z2 - $z1) / $width;
                $du = ($u2 - $u1) / $width;
                $dv = ($v2 - $v1) / $width;
                $dl = ($light2 - $light1) / $width;
            }
            my ($x,  $z,  $u,  $v,  $light) = $x1 > $x2
             ? ($x2, $z2, $u2, $v2, $light2)
             : ($x1, $z1, $u1, $v1, $light1);

            my $x_max = $x1 > $x2 ? $x1 : $x2;
            while( $x <= $x_max )
            {
                if( $Mode == 0 )
                {
                    my $color = ($z + $scr_z / 2 + 1) * 0.9 / $scr_z;
                    Vector->new($x, $y, $z)->draw([$color, $color, $color]);
                }
                 elsif( $Mode == 1 )
                {
                    Vector->new($x, $y, $z)->draw([$light, $light, $light]);
                }
                 else
                {
                    my $uu = int($u);
                    my $vv = int($v_max-$v);
                    $uu = $u_max - 1 if $uu > $u_max - 1;
                    $uu = 0 if $uu < 0;
                    $vv = 0 if $vv < 0;
                    my $color = [$texture_image->GetPixel(x=>$uu, y=>$vv)];
                    if( $Mode == 2 )
                    {
                    }
                     elsif( $Mode == 3 )
                    {
                        $color = [ map{ $_ * $light } @$color ];
                    }
                     elsif( $Mode == 4 )
                    {
                        #normals = self.normals_map[uu][vv]
                        #n_light = int(sum([normals[i] * light_vector[i] for i in(0, 1, 2)])*256)
                        #color = (n_light,) * 3
                    }
                     else
                    {
                        #normals = self.normals_map[uu][vv]
                        #n_light = sum([normals[i] * light_vector[i] for i in(0, 1, 2)])
                        #mirror = [light_vector[i] - 2 * normals[i] * n_light for i in(0, 1, 2)]
                        #specular = 0.02 * pow(sum([mirror[i] * eye_vector[i] for i in(0, 1, 2)]), 4)
                        #intensity = 1 * float(n_light + specular)
                        #color = [int(i * intensity) for i in color];
                    }
                    if( $color )
                    {
                        Vector->new($x, $y, $z)->draw($color);
                    }
                }
                $x += 1;
                $z += $dz;
                $u += $du;
                $v += $dv;
                $light += $dl;
            }
            $y += 1;
            $x1 += $delta_bx;
            $x2 += $delta_cx;
            $z1 += $delta_bz;
            $z2 += $delta_cz;
            $u1 += $delta_u1;
            $u2 += $delta_u2;
            $v1 += $delta_v1;
            $v2 += $delta_v2;
            $light1 += $delta_b_light;
            $light2 += $delta_c_light;
        }
    }
}

package Canvas;
use strict;

my $image;
my($scr_x, $scr_y, $scr_z, $center_x, $center_y);
my %z_buffer = ();

sub new
{
    (undef, $scr_x, $scr_y, $scr_z) = @_;
    $image = Image::Magick->new(
        size  => $scr_x.'x'.$scr_y,
        type  => 'RGB',
        depth => 24,
    );
    $image->Read('xc:black');

    $scr_x--;
    $scr_y--;
    $scr_z--;

    $center_x = int($scr_x / 2);
    $center_y = int($scr_y / 2);
}

sub SetPixel
{
    my(undef, %p) = @_;
    my $index = $p{x}.':'.$p{y};
    return if $z_buffer{$index} > $p{z};
    $z_buffer{$index} = $p{z};
    $p{x} = $center_x + $p{x};
    $p{y} = $center_y - $p{y};
    delete $p{z};
    $image->SetPixel(%p);
}

sub show
{
    my $res = $image->Write( filename => 'face.png' );
    warn $res if $res;
}

package Vector;
use strict;

sub new
{
    my $class = shift;
    return bless {
        x => $_[0],
        y => $_[1],
        z => $_[2],
    }, $class;
}

sub draw
{
    my($self, $color) = @_;
    my($x, $y, $z) = ( int($self->{x}+0.5), int($self->{y}+0.5), int($self->{z}+0.5) );
    Canvas->SetPixel(
        x     => $x,
        y     => $y,
        z     => $z,
        color => $color,
    );
}
